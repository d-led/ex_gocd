# Copyright 2026 ex_gocd
# Controller for handling artifact uploads and downloads (POST/GET/PUT /files/...)
# Supports directory zipping, secure unzipping (Zip Slip protection), and DB-backed console log integration.

defmodule ExGoCDWeb.ArtifactsController do
  use ExGoCDWeb, :controller

  require Logger

  # Helper to determine where artifacts are stored
  defp artifacts_dir do
    System.get_env("ARTIFACTS_DIR") || "artifacts"
  end

  # POST /files/:pipeline_name/:pipeline_counter/:stage_name/:stage_counter/:job_name/*file_path
  def create(conn, %{
        "pipeline_name" => pipeline_name,
        "pipeline_counter" => pipeline_counter_str,
        "stage_name" => stage_name,
        "stage_counter" => stage_counter_str,
        "job_name" => job_name,
        "file_path" => file_path
      }) do
    pipeline_counter = parse_integer(pipeline_counter_str)
    stage_counter = parse_integer(stage_counter_str)

    # 1. Security Check: prevent directory traversal
    if not safe_segments?(file_path) do
      conn
      |> put_status(403)
      |> text("Forbidden: Invalid path segments.")
    else
      job_dir = Path.expand(Path.join([
        artifacts_dir(),
        pipeline_name,
        to_string(pipeline_counter),
        stage_name,
        to_string(stage_counter),
        job_name
      ]))

      target_path = Path.expand(Path.join([job_dir | file_path]))

      # Enforce trailing slash or strict prefix checks for directory boundaries
      if not verify_boundary(target_path, job_dir) do
        conn
        |> put_status(403)
        |> text("Forbidden: Path escapes boundary.")
      else
        # If target path already exists as file, return 403 (GoCD requirement)
        if File.exists?(target_path) and File.regular?(target_path) do
          conn
          |> put_status(403)
          |> text("File #{Path.join(file_path)} already exists.")
        else
          upload = conn.params["file"] || conn.params["zipfile"]
          checksum_upload = conn.params["file_checksum"]

          cond do
            is_nil(upload) ->
              conn
              |> put_status(400)
              |> text("Bad Request: Missing upload file.")

            conn.params["zipfile"] ->
              # Zipped directory upload. Securely extract it (Zip Slip protection)
              case extract_zip_securely(upload.path, target_path) do
                :ok ->
                  if checksum_upload do
                    save_checksum(job_dir, checksum_upload)
                  end

                  conn
                  |> put_status(201)
                  |> text("File was created successfully")

                {:error, :directory_traversal} ->
                  conn
                  |> put_status(403)
                  |> text("Forbidden: Zip file contains directory traversal.")

                {:error, reason} ->
                  Logger.error("Unzip error: #{inspect(reason)}")
                  conn
                  |> put_status(500)
                  |> text("Internal Server Error: Failed to extract zip.")
              end

            true ->
              # Regular single file upload
              File.mkdir_p!(Path.dirname(target_path))

              case File.copy(upload.path, target_path) do
                {:ok, _} ->
                  if checksum_upload do
                    save_checksum(job_dir, checksum_upload)
                  end

                  conn
                  |> put_status(201)
                  |> text("File was created successfully")

                {:error, reason} ->
                  Logger.error("File copy error: #{inspect(reason)}")
                  conn
                  |> put_status(500)
                  |> text("Internal Server Error: Failed to copy file.")
              end
          end
        end
      end
    end
  end

  # GET /files/:pipeline_name/:pipeline_counter/:stage_name/:stage_counter/:job_name/*file_path
  def show(conn, %{
        "pipeline_name" => pipeline_name,
        "pipeline_counter" => pipeline_counter_str,
        "stage_name" => stage_name,
        "stage_counter" => stage_counter_str,
        "job_name" => job_name,
        "file_path" => file_path
      }) do
    pipeline_counter = parse_integer(pipeline_counter_str)
    stage_counter = parse_integer(stage_counter_str)

    if not safe_segments?(file_path) do
      conn
      |> put_status(403)
      |> text("Forbidden: Invalid path segments.")
    else
      job_dir = Path.expand(Path.join([
        artifacts_dir(),
        pipeline_name,
        to_string(pipeline_counter),
        stage_name,
        to_string(stage_counter),
        job_name
      ]))

      target_path = Path.expand(Path.join([job_dir | file_path]))

      if not verify_boundary(target_path, job_dir) do
        conn
        |> put_status(403)
        |> text("Forbidden: Path escapes boundary.")
      else
        cond do
          # Special integration: if console.log is requested, serve from database (centralized logs)
          Path.join(file_path) == "cruise-output/console.log" ->
            case get_run_by_params(pipeline_name, pipeline_counter, stage_name, stage_counter, job_name) do
              nil ->
                conn
                |> put_status(404)
                |> text("Console log not found.")

              run ->
                conn
                |> put_resp_header("content-type", "text/plain; charset=utf-8")
                |> send_resp(200, run.console_log || "")
            end

          File.regular?(target_path) ->
            content_type = MIME.from_path(target_path)
            conn
            |> put_resp_header("content-type", content_type)
            |> send_file(200, target_path)

          File.dir?(target_path) ->
            # If zip is requested (either URL ends with .zip or Accept header asks for zip), return directory zip
            is_zip_request? = String.ends_with?(conn.request_path, ".zip") or
              String.contains?(get_req_header(conn, "accept") |> List.first() || "", "zip")

            if is_zip_request? do
              files_to_zip = list_files_recursive(target_path)
              |> Enum.map(fn abs_path ->
                rel_path = Path.relative_to(abs_path, target_path)
                {to_charlist(rel_path), File.read!(abs_path)}
              end)

              case :zip.create(~c"archive.zip", files_to_zip, [:memory]) do
                {:ok, {~c"archive.zip", binary}} ->
                  conn
                  |> put_resp_header("content-type", "application/zip")
                  |> send_resp(200, binary)

                {:error, reason} ->
                  Logger.error("Zip compression failed: #{inspect(reason)}")
                  conn
                  |> put_status(500)
                  |> text("Internal Server Error: Failed to zip directory.")
              end
            else
              # Otherwise, return JSON directory index
              case File.ls(target_path) do
                {:ok, files} ->
                  list = Enum.map(files, fn name ->
                    full_path = Path.join(target_path, name)
                    type = if File.dir?(full_path), do: "folder", else: "file"
                    %{name: name, type: type}
                  end)
                  json(conn, list)

                {:error, _} ->
                  conn
                  |> put_status(500)
                  |> text("Failed to list folder.")
              end
            end

          true ->
            # Not found
            conn
            |> put_status(404)
            |> text("Artifact '#{Path.join(file_path)}' is unavailable as it may have been purged by Go or deleted externally.")
        end
      end
    end
  end

  # PUT /files/:pipeline_name/:pipeline_counter/:stage_name/:stage_counter/:job_name/*file_path
  def update(conn, %{
        "pipeline_name" => pipeline_name,
        "pipeline_counter" => pipeline_counter_str,
        "stage_name" => stage_name,
        "stage_counter" => stage_counter_str,
        "job_name" => job_name,
        "file_path" => file_path
      }) do
    pipeline_counter = parse_integer(pipeline_counter_str)
    stage_counter = parse_integer(stage_counter_str)

    if not safe_segments?(file_path) do
      conn
      |> put_status(403)
      |> text("Forbidden: Invalid path segments.")
    else
      job_dir = Path.expand(Path.join([
        artifacts_dir(),
        pipeline_name,
        to_string(pipeline_counter),
        stage_name,
        to_string(stage_counter),
        job_name
      ]))

      target_path = Path.expand(Path.join([job_dir | file_path]))

      if not verify_boundary(target_path, job_dir) do
        conn
        |> put_status(403)
        |> text("Forbidden: Path escapes boundary.")
      else
        case read_body(conn) do
          {:ok, body, conn2} ->
            cond do
              Path.join(file_path) == "cruise-output/console.log" ->
                # Console logs uploaded by agents: append to database run
                case get_run_by_params(pipeline_name, pipeline_counter, stage_name, stage_counter, job_name) do
                  nil ->
                    conn2
                    |> put_status(404)
                    |> text("Job run not found.")

                  run ->
                    case ExGoCD.AgentJobRuns.append_console(run.build_id, body) do
                      {:ok, _} ->
                        conn2
                        |> put_status(200)
                        |> text("File cruise-output/console.log was appended successfully")
                      _ ->
                        conn2
                        |> put_status(500)
                        |> text("Failed to append to log.")
                    end
                end

              true ->
                # File append on disk
                File.mkdir_p!(Path.dirname(target_path))
                mode = if File.exists?(target_path), do: [:append], else: [:write]
                case File.write(target_path, body, mode) do
                  :ok ->
                    conn2
                    |> put_status(200)
                    |> text("File #{Path.join(file_path)} was appended successfully")
                  {:error, reason} ->
                    Logger.error("PUT write error: #{inspect(reason)}")
                    conn2
                    |> put_status(500)
                    |> text("Failed to append to file.")
                end
            end
        end
      end
    end
  end

  # Helper to parse integer safely
  defp parse_integer(str, default \\ 1) do
    case Integer.parse(str || "") do
      {num, _} -> num
      :error -> default
    end
  end

  # Helper to validate that no path segments escape via directory traversal
  defp safe_segments?(segments) do
    Enum.all?(segments, fn seg ->
      seg != ".." and not String.contains?(seg, "/") and not String.contains?(seg, "\\")
    end)
  end

  # Verify target path is strictly within the job directory boundary
  defp verify_boundary(path, job_dir) do
    path = Path.expand(path)
    job_dir = Path.expand(job_dir)
    # Enforce trailing slash to prevent partial name matches
    job_dir_with_slash = if String.ends_with?(job_dir, "/"), do: job_dir, else: job_dir <> "/"
    String.starts_with?(path, job_dir_with_slash) or path == job_dir
  end

  # Secure zip extraction (Zip Slip protection)
  defp extract_zip_securely(zip_path, dest_dir) do
    dest_dir = Path.expand(dest_dir)

    case :zip.table(to_charlist(zip_path)) do
      {:ok, entries} ->
        traversal? = Enum.any?(entries, fn entry ->
          name = get_entry_name(entry)
          cleaned_name = String.replace(name, "\\", "/")
          
          String.contains?(cleaned_name, "..") or
            String.starts_with?(cleaned_name, "/") or
            not verify_boundary(Path.join(dest_dir, cleaned_name), dest_dir)
        end)

        if traversal? do
          {:error, :directory_traversal}
        else
          File.mkdir_p!(dest_dir)
          case :zip.unzip(to_charlist(zip_path), [{:cwd, to_charlist(dest_dir)}]) do
            {:ok, _} -> :ok
            {:error, reason} -> {:error, reason}
          end
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_entry_name(entry) do
    cond do
      is_tuple(entry) and tuple_size(entry) >= 2 ->
        name_val = elem(entry, 1)
        cond do
          is_list(name_val) -> List.to_string(name_val)
          is_binary(name_val) -> name_val
          true -> ""
        end
      true ->
        ""
    end
  end

  # Appends a checksum line to cruise-output/md5.checksum
  defp save_checksum(job_dir, checksum_upload) do
    checksum_file_path = Path.join([job_dir, "cruise-output", "md5.checksum"])
    File.mkdir_p!(Path.dirname(checksum_file_path))

    content = File.read!(checksum_upload.path)
    content = if String.ends_with?(content, "\n"), do: content, else: content <> "\n"
    File.write!(checksum_file_path, content, [:append])
  end

  # Recursive lister for zipping folders
  defp list_files_recursive(dir) do
    cond do
      File.dir?(dir) ->
        File.ls!(dir)
        |> Enum.flat_map(fn name ->
          path = Path.join(dir, name)
          list_files_recursive(path)
        end)

      File.regular?(dir) ->
        [dir]

      true ->
        []
    end
  end

  # Retrieves job run from the database based on pipeline coordinates
  defp get_run_by_params(pipeline_name, pipeline_counter, stage_name, stage_counter, job_name) do
    import Ecto.Query
    from(r in ExGoCD.AgentJobRuns.AgentJobRun,
      where: r.pipeline_name == ^pipeline_name
        and r.pipeline_counter == ^pipeline_counter
        and r.stage_name == ^stage_name
        and r.stage_counter == ^stage_counter
        and r.job_name == ^job_name,
      order_by: [desc: r.inserted_at],
      limit: 1
    )
    |> ExGoCD.Repo.one()
  end
end
