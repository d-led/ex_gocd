defmodule ExGoCDWeb.ArtifactsControllerTest do
  use ExGoCDWeb.ConnCase, async: false

  alias ExGoCD.AgentJobRuns.AgentJobRun
  alias ExGoCD.Repo

  setup do
    # Temporarily set ARTIFACTS_DIR to a test directory
    test_dir = Path.join([System.tmp_dir!(), "ex_gocd_test_artifacts_#{System.unique_integer([:positive])}"])
    System.put_env("ARTIFACTS_DIR", test_dir)
    File.mkdir_p!(test_dir)

    on_exit(fn ->
      File.rm_rf!(test_dir)
      System.delete_env("ARTIFACTS_DIR")
    end)

    {:ok, artifacts_dir: test_dir}
  end

  describe "POST /files/:pipeline_name/:pipeline_counter/:stage_name/:stage_counter/:job_name/*file_path" do
    test "uploads a single file successfully", %{conn: conn, artifacts_dir: artifacts_dir} do
      temp_file = Path.join(System.tmp_dir!(), "upload_test.txt")
      File.write!(temp_file, "file contents here")

      upload = %Plug.Upload{
        content_type: "text/plain",
        filename: "upload_test.txt",
        path: temp_file
      }

      conn =
        post(
          conn,
          ~p"/files/test_pipeline/1/test_stage/1/test_job/path/to/target.txt",
          %{file: upload}
        )

      assert response(conn, 201) =~ "created successfully"

      expected_path = Path.join([artifacts_dir, "test_pipeline", "1", "test_stage", "1", "test_job", "path", "to", "target.txt"])
      assert File.read!(expected_path) == "file contents here"
    end

    test "uploads a zipped directory and extracts it securely", %{conn: conn, artifacts_dir: artifacts_dir} do
      # 1. Create a temporary zip file
      temp_src = Path.join(System.tmp_dir!(), "zip_src_#{System.unique_integer([:positive])}")
      File.mkdir_p!(temp_src)
      File.write!(Path.join(temp_src, "a.txt"), "content a")
      File.write!(Path.join(temp_src, "b.txt"), "content b")

      temp_zip = Path.join(System.tmp_dir!(), "dir_#{System.unique_integer([:positive])}.zip")
      files = [{"a.txt", Path.join(temp_src, "a.txt")}, {"b.txt", Path.join(temp_src, "b.txt")}]
      files_char = Enum.map(files, fn {name, path} -> {to_charlist(name), File.read!(path)} end)
      {:ok, _} = :zip.create(to_charlist(temp_zip), files_char)

      upload = %Plug.Upload{
        content_type: "application/zip",
        filename: "dir.zip",
        path: temp_zip
      }

      # 2. Upload zip
      conn =
        post(
          conn,
          ~p"/files/test_pipeline/1/test_stage/1/test_job/extracted_folder",
          %{zipfile: upload}
        )

      assert response(conn, 201) =~ "created successfully"

      # 3. Check extracted contents
      extracted_dir = Path.join([artifacts_dir, "test_pipeline", "1", "test_stage", "1", "test_job", "extracted_folder"])
      assert File.read!(Path.join(extracted_dir, "a.txt")) == "content a"
      assert File.read!(Path.join(extracted_dir, "b.txt")) == "content b"

      # Cleanup
      File.rm_rf!(temp_src)
      File.rm(temp_zip)
    end

    test "blocks path traversal segments in URL path", %{conn: conn} do
      temp_file = Path.join(System.tmp_dir!(), "traversal_test.txt")
      File.write!(temp_file, "traversal contents")

      upload = %Plug.Upload{
        content_type: "text/plain",
        filename: "traversal_test.txt",
        path: temp_file
      }

      conn =
        post(
          conn,
          "/files/test_pipeline/1/test_stage/1/test_job/path/../../escaped.txt",
          %{file: upload}
        )

      assert response(conn, 403) =~ "Forbidden"
      File.rm(temp_file)
    end

    test "blocks zip slip (directory traversal in zip entries)", %{conn: conn, artifacts_dir: artifacts_dir} do
      # 1. Create a zip with malicious entry name `../outside.txt`
      temp_src = Path.join(System.tmp_dir!(), "malicious_src_#{System.unique_integer([:positive])}")
      File.mkdir_p!(temp_src)
      File.write!(Path.join(temp_src, "malicious.txt"), "evil")

      temp_zip = Path.join(System.tmp_dir!(), "evil_#{System.unique_integer([:positive])}.zip")
      files_char = [{to_charlist("../outside.txt"), File.read!(Path.join(temp_src, "malicious.txt"))}]
      {:ok, _} = :zip.create(to_charlist(temp_zip), files_char)

      upload = %Plug.Upload{
        content_type: "application/zip",
        filename: "evil.zip",
        path: temp_zip
      }

      # 2. Upload zip
      conn =
        post(
          conn,
          ~p"/files/test_pipeline/1/test_stage/1/test_job/extracted_folder",
          %{zipfile: upload}
        )

      assert response(conn, 403) =~ "directory traversal"

      # 3. Verify it was not written outside the job directory
      escaped_path = Path.join([artifacts_dir, "test_pipeline", "1", "test_stage", "1", "outside.txt"])
      refute File.exists?(escaped_path)

      # Cleanup
      File.rm_rf!(temp_src)
      File.rm(temp_zip)
    end
  end

  describe "GET /files/:pipeline_name/:pipeline_counter/:stage_name/:stage_counter/:job_name/*file_path" do
    test "serves regular file with correct mime type", %{conn: conn, artifacts_dir: artifacts_dir} do
      job_dir = Path.join([artifacts_dir, "test_pipeline", "1", "test_stage", "1", "test_job"])
      File.mkdir_p!(job_dir)
      File.write!(Path.join(job_dir, "info.json"), "{\"status\":\"ok\"}")

      conn = get(conn, ~p"/files/test_pipeline/1/test_stage/1/test_job/info.json")
      assert json_response(conn, 200) == %{"status" => "ok"}
      assert get_resp_header(conn, "content-type") |> List.first() =~ "application/json"
    end

    test "serves directory dynamically zipped when accept contains zip", %{conn: conn, artifacts_dir: artifacts_dir} do
      job_dir = Path.join([artifacts_dir, "test_pipeline", "1", "test_stage", "1", "test_job"])
      dir_to_zip = Path.join(job_dir, "to_zip")
      File.mkdir_p!(dir_to_zip)
      File.write!(Path.join(dir_to_zip, "x.txt"), "hello x")

      conn =
        conn
        |> put_req_header("accept", "application/zip")
        |> get(~p"/files/test_pipeline/1/test_stage/1/test_job/to_zip")

      assert response_content_type(conn, :zip) == "application/zip"
      body = response(conn, 200)
      assert byte_size(body) > 0
    end

    test "serves centralized console log from database", %{conn: conn} do
      # Insert mock job run
      %AgentJobRun{}
      |> AgentJobRun.changeset(%{
        agent_uuid: "test-agent",
        build_id: "test-build",
        pipeline_name: "test_pipeline",
        pipeline_counter: 1,
        stage_name: "test_stage",
        stage_counter: 1,
        job_name: "test_job",
        console_log: "Line 1\nLine 2\n"
      })
      |> Repo.insert!()

      conn = get(conn, ~p"/files/test_pipeline/1/test_stage/1/test_job/cruise-output/console.log")
      assert response(conn, 200) == "Line 1\nLine 2\n"
      assert get_resp_header(conn, "content-type") |> List.first() =~ "text/plain"
    end
  end

  describe "PUT /files/:pipeline_name/:pipeline_counter/:stage_name/:stage_counter/:job_name/*file_path" do
    test "appends content to database console log", %{conn: conn} do
      # Insert mock job run
      run =
        %AgentJobRun{}
        |> AgentJobRun.changeset(%{
          agent_uuid: "test-agent",
          build_id: "test-build",
          pipeline_name: "test_pipeline",
          pipeline_counter: 1,
          stage_name: "test_stage",
          stage_counter: 1,
          job_name: "test_job",
          console_log: "Initial\n"
        })
        |> Repo.insert!()

      conn =
        conn
        |> put_req_header("content-type", "text/plain")
        |> put(~p"/files/test_pipeline/1/test_stage/1/test_job/cruise-output/console.log", "Appended line\n")

      assert response(conn, 200) =~ "appended successfully"

      # Check DB log content
      updated_run = Repo.get!(AgentJobRun, run.id)
      assert updated_run.console_log == "Initial\nAppended line\n"
    end

    test "appends content to regular file on disk", %{conn: conn, artifacts_dir: artifacts_dir} do
      job_dir = Path.join([artifacts_dir, "test_pipeline", "1", "test_stage", "1", "test_job"])
      file_path = Path.join(job_dir, "log.txt")
      File.mkdir_p!(job_dir)
      File.write!(file_path, "Line 1\n")

      conn =
        conn
        |> put_req_header("content-type", "text/plain")
        |> put(~p"/files/test_pipeline/1/test_stage/1/test_job/log.txt", "Line 2\n")

      assert response(conn, 200) =~ "appended successfully"
      assert File.read!(file_path) == "Line 1\nLine 2\n"
    end
  end
end
