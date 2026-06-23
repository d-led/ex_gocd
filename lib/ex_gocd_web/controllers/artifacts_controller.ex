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

  # Constructs job_dir and target_path from URL path params
  defp build_job_paths(
         pipeline_name,
         pipeline_counter_str,
         stage_name,
         stage_counter_str,
         job_name,
         file_path
       ) do
    pipeline_counter = parse_integer(pipeline_counter_str)
    stage_counter = parse_integer(stage_counter_str)

    job_dir =
      Path.expand(
        Path.join([
          artifacts_dir(),
          pipeline_name,
          to_string(pipeline_counter),
          stage_name,
          to_string(stage_counter),
          job_name
        ])
      )

    target_path = Path.expand(Path.join([job_dir | file_path]))

    {pipeline_counter, stage_counter, job_dir, target_path}
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
    {_pipeline_counter, _stage_counter, job_dir, target_path} =
      build_job_paths(
        pipeline_name,
        pipeline_counter_str,
        stage_name,
        stage_counter_str,
        job_name,
        file_path
      )

    with :ok <- check_safe_segments(file_path),
         :ok <- check_boundary(target_path, job_dir),
         :ok <- check_file_not_exists(target_path, file_path) do
      upload = conn.params["file"] || conn.params["zipfile"]
      checksum_upload = conn.params["file_checksum"]
      handle_upload(conn, upload, checksum_upload, target_path, job_dir)
    else
      {:error, status, message} ->
        conn |> put_status(status) |> text(message)
    end
  end

  defp check_safe_segments(file_path) do
    if safe_segments?(file_path) do
      :ok
    else
      {:error, 403, "Forbidden: Invalid path segments."}
    end
  end

  defp check_boundary(target_path, job_dir) do
    if verify_boundary(target_path, job_dir) do
      :ok
    else
      {:error, 403, "Forbidden: Path escapes boundary."}
    end
  end

  defp check_file_not_exists(target_path, file_path) do
    if File.exists?(target_path) and File.regular?(target_path) do
      {:error, 403, "File #{Path.join(file_path)} already exists."}
    else
      :ok
    end
  end

  defp handle_upload(conn, nil, _checksum, _target_path, _job_dir) do
    conn |> put_status(400) |> text("Bad Request: Missing upload file.")
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp handle_upload(conn, upload, checksum_upload, target_path, job_dir) do
    if conn.params["zipfile"] do
      # Zipped directory upload
      case extract_zip_securely(upload.path, target_path) do
        :ok ->
          maybe_save_checksum(job_dir, checksum_upload)
          compute_and_save_checksums(target_path, job_dir)
          maybe_generate_test_report(job_dir)
          ExGoCD.ArtifactCleanup.cleanup_if_needed()
          conn |> put_status(201) |> text("File was created successfully")

        {:error, :directory_traversal} ->
          conn |> put_status(403) |> text("Forbidden: Zip file contains directory traversal.")

        {:error, reason} ->
          Logger.error("Unzip error: #{inspect(reason)}")
          conn |> put_status(500) |> text("Internal Server Error: Failed to extract zip.")
      end
    else
      # Regular single file upload
      File.mkdir_p!(Path.dirname(target_path))

      case File.copy(upload.path, target_path) do
        {:ok, _} ->
          maybe_save_checksum(job_dir, checksum_upload)
          compute_and_save_checksum(target_path, job_dir)
          maybe_generate_test_report(job_dir)
          ExGoCD.ArtifactCleanup.cleanup_if_needed()
          conn |> put_status(201) |> text("File was created successfully")

        {:error, reason} ->
          Logger.error("File copy error: #{inspect(reason)}")
          conn |> put_status(500) |> text("Internal Server Error: Failed to copy file.")
      end
    end
  end

  defp maybe_save_checksum(job_dir, %{path: _} = checksum_upload) do
    save_checksum(job_dir, checksum_upload)
  end

  defp maybe_save_checksum(_job_dir, _), do: :ok

  # Trigger test report generation if testoutput/ exists with XML files
  defp maybe_generate_test_report(job_dir) do
    test_dir = Path.join(job_dir, "testoutput")

    if File.dir?(test_dir) do
      case File.ls(test_dir) do
        {:ok, files} ->
          if Enum.any?(files, &String.ends_with?(&1, ".xml")) do
            ExGoCD.TestReport.generate(job_dir)
          end

        {:error, _} ->
          :ok
      end
    end

    :ok
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
    {pipeline_counter, stage_counter, job_dir, target_path} =
      build_job_paths(
        pipeline_name,
        pipeline_counter_str,
        stage_name,
        stage_counter_str,
        job_name,
        file_path
      )

    with :ok <- check_safe_segments(file_path),
         :ok <- check_boundary(target_path, job_dir) do
      # Route to appropriate content provider
      cond do
        Path.join(file_path) == "cruise-output/console.log" ->
          serve_console_log(
            conn,
            pipeline_name,
            pipeline_counter,
            stage_name,
            stage_counter,
            job_name
          )

        File.regular?(target_path) ->
          serve_file(conn, target_path)

        File.dir?(target_path) ->
          serve_directory(conn, target_path)

        true ->
          serve_not_found(conn, file_path)
      end
    else
      {:error, status, message} ->
        conn |> put_status(status) |> text(message)
    end
  end

  # sobelow_skip ["XSS.SendResp"]
  defp serve_console_log(
         conn,
         pipeline_name,
         pipeline_counter,
         stage_name,
         stage_counter,
         job_name
       ) do
    case get_run_by_params(pipeline_name, pipeline_counter, stage_name, stage_counter, job_name) do
      nil ->
        conn |> put_status(404) |> text("Console log not found.")

      run ->
        conn
        |> put_resp_header("content-type", "text/plain; charset=utf-8")
        |> text(run.console_log || "")
    end
  end

  # sobelow_skip ["Traversal.SendFile"]
  defp serve_file(conn, target_path) do
    verify_checksum_on_fetch(target_path)
    content_type = MIME.from_path(target_path)

    conn
    |> put_resp_header("content-type", content_type)
    |> send_file(200, target_path)
  end

  # Verifies the MD5 checksum of the served file against the stored checksum.
  # Logs a warning if mismatch (does not block serving — GoCD behavior).
  defp verify_checksum_on_fetch(target_path) do
    job_dir = Path.dirname(target_path)
    checksum_file = Path.join(job_dir, "md5.checksum")
    file_name = Path.basename(target_path)

    if File.exists?(checksum_file) and File.exists?(target_path) do
      stored = stored_checksum_for(checksum_file, file_name)

      if stored do
        computed = :crypto.hash(:md5, File.read!(target_path)) |> Base.encode16(case: :lower)

        unless computed == stored do
          require Logger

          Logger.warning(
            "Artifact checksum mismatch for #{file_name}: stored=#{stored}, computed=#{computed}"
          )
        end
      end
    end
  rescue
    _ -> :ok
  end

  defp stored_checksum_for(checksum_file, file_name) do
    File.stream!(checksum_file)
    |> Enum.find_value(fn line ->
      case String.split(String.trim(line), "  ") do
        [sum, ^file_name] -> String.trim(sum)
        _ -> nil
      end
    end)
  rescue
    _ -> nil
  end

  defp serve_directory(conn, target_path) do
    is_zip? =
      String.ends_with?(conn.request_path, ".zip") or
        String.contains?(get_req_header(conn, "accept") |> List.first() || "", "zip")

    if is_zip? do
      serve_directory_as_zip(conn, target_path)
    else
      serve_directory_index(conn, target_path)
    end
  end

  # sobelow_skip ["Traversal.FileModule", "XSS.SendResp"]
  defp serve_directory_as_zip(conn, target_path) do
    files_to_zip =
      list_files_recursive(target_path)
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
  end

  defp serve_directory_index(conn, target_path) do
    case File.ls(target_path) do
      {:ok, files} ->
        list = Enum.map(files, &file_entry(target_path, &1))
        json(conn, list)

      {:error, _} ->
        conn
        |> put_status(500)
        |> text("Failed to list folder.")
    end
  end

  defp file_entry(parent_path, name) do
    type = if File.dir?(Path.join(parent_path, name)), do: "folder", else: "file"
    %{name: name, type: type}
  end

  defp serve_not_found(conn, file_path) do
    conn
    |> put_status(404)
    |> text(
      "Artifact '#{Path.join(file_path)}' is unavailable as it may have been purged by Go or deleted externally."
    )
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
    {pipeline_counter, stage_counter, job_dir, target_path} =
      build_job_paths(
        pipeline_name,
        pipeline_counter_str,
        stage_name,
        stage_counter_str,
        job_name,
        file_path
      )

    with :ok <- check_safe_segments(file_path),
         :ok <- check_boundary(target_path, job_dir),
         {:ok, body, conn2} <- read_body(conn) do
      if Path.join(file_path) == "cruise-output/console.log" do
        handle_console_log_append(
          conn2,
          pipeline_name,
          pipeline_counter,
          stage_name,
          stage_counter,
          job_name,
          body
        )
      else
        handle_file_append(conn2, target_path, file_path, body)
      end
    else
      {:error, status, message} ->
        conn |> put_status(status) |> text(message)
    end
  end

  defp handle_console_log_append(
         conn,
         pipeline_name,
         pipeline_counter,
         stage_name,
         stage_counter,
         job_name,
         body
       ) do
    case get_run_by_params(pipeline_name, pipeline_counter, stage_name, stage_counter, job_name) do
      nil ->
        conn |> put_status(404) |> text("Job run not found.")

      run ->
        case ExGoCD.AgentJobRuns.append_console(run.build_id, body) do
          {:ok, _} ->
            conn
            |> put_status(200)
            |> text("File cruise-output/console.log was appended successfully")

          _ ->
            conn |> put_status(500) |> text("Failed to append to log.")
        end
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp handle_file_append(conn, target_path, file_path, body) do
    File.mkdir_p!(Path.dirname(target_path))
    mode = if File.exists?(target_path), do: [:append], else: [:write]

    case File.write(target_path, body, mode) do
      :ok ->
        conn |> put_status(200) |> text("File #{Path.join(file_path)} was appended successfully")

      {:error, reason} ->
        Logger.error("PUT write error: #{inspect(reason)}")
        conn |> put_status(500) |> text("Failed to append to file.")
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
  # sobelow_skip ["Traversal.FileModule"]
  defp extract_zip_securely(zip_path, dest_dir) do
    dest_dir = Path.expand(dest_dir)

    case :zip.table(to_charlist(zip_path)) do
      {:ok, entries} ->
        if check_zip_traversal(entries, dest_dir) do
          {:error, :directory_traversal}
        else
          File.mkdir_p!(dest_dir)
          unzip_to_directory(zip_path, dest_dir)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp check_zip_traversal(entries, dest_dir) do
    Enum.any?(entries, fn entry ->
      name = get_entry_name(entry)
      cleaned_name = String.replace(name, "\\", "/")

      String.contains?(cleaned_name, "..") or
        String.starts_with?(cleaned_name, "/") or
        not verify_boundary(Path.join(dest_dir, cleaned_name), dest_dir)
    end)
  end

  defp unzip_to_directory(zip_path, dest_dir) do
    case :zip.unzip(to_charlist(zip_path), [{:cwd, to_charlist(dest_dir)}]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_entry_name(entry) when is_tuple(entry) and tuple_size(entry) >= 2 do
    case elem(entry, 1) do
      name_val when is_list(name_val) -> List.to_string(name_val)
      name_val when is_binary(name_val) -> name_val
      _ -> ""
    end
  end

  defp get_entry_name(_), do: ""

  # Appends a checksum line to cruise-output/md5.checksum
  # sobelow_skip ["Traversal.FileModule"]
  defp save_checksum(job_dir, checksum_upload) do
    checksum_file_path = Path.join([job_dir, "cruise-output", "md5.checksum"])
    File.mkdir_p!(Path.dirname(checksum_file_path))

    content = File.read!(checksum_upload.path)
    content = if String.ends_with?(content, "\n"), do: content, else: content <> "\n"
    File.write!(checksum_file_path, content, [:append])
  end

  # Computes MD5 checksum for a single file and appends to manifest
  # sobelow_skip ["Traversal.FileModule"]
  defp compute_and_save_checksum(file_path, job_dir) do
    checksum = file_md5(file_path)
    rel_path = Path.relative_to(file_path, job_dir)
    line = "#{checksum}  #{rel_path}\n"

    manifest_path = Path.join([job_dir, "cruise-output", "md5.checksum"])
    File.mkdir_p!(Path.dirname(manifest_path))

    # Only append if this file isn't already in the manifest
    existing = File.exists?(manifest_path) && File.read!(manifest_path)

    unless existing && String.contains?(existing, "  #{rel_path}") do
      File.write!(manifest_path, line, [:append])
    end
  end

  # Computes MD5 checksums for all files in a directory (after zip extraction)
  # sobelow_skip ["Traversal.FileModule"]
  defp compute_and_save_checksums(dir_path, job_dir) do
    if File.dir?(dir_path) do
      dir_path
      |> list_files_recursive()
      |> Enum.each(&compute_and_save_checksum(&1, job_dir))
    else
      compute_and_save_checksum(dir_path, job_dir)
    end
  end

  # Computes MD5 hash of a file
  # sobelow_skip ["Traversal.FileModule"]
  defp file_md5(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        :crypto.hash(:md5, content) |> Base.encode16(case: :lower)

      {:error, _} ->
        "00000000000000000000000000000000"
    end
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
    ExGoCD.AgentJobRuns.get_run_by_params(
      pipeline_name,
      pipeline_counter,
      stage_name,
      stage_counter,
      job_name
    )
  end
end
