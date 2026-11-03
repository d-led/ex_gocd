defmodule ExGoCD.ConfigRepos.FetcherTest do
  # A real git repository in a temporary directory: discovery clones and reads it,
  # the same way it does for a configuration repository the user typed in.
  use ExUnit.Case, async: false

  alias ExGoCD.ConfigRepos.Fetcher

  @moduletag :tmp_dir

  test "lists the workflow files the repository has, with the jobs each defines",
       %{tmp_dir: tmp_dir} do
    origin =
      git_repository(tmp_dir, %{
        ".github/workflows/build.yml" => workflow(["compile", "test"]),
        ".github/workflows/release.yaml" => workflow(["publish"])
      })

    repo = %{
      id: unique_repository_id(),
      url: origin,
      branch: "main",
      source_type: "github_actions"
    }

    assert {:ok, files} = Fetcher.discover(repo)

    assert files == [
             %{path: ".github/workflows/build.yml", job_names: ["compile", "test"]},
             %{path: ".github/workflows/release.yaml", job_names: ["publish"]}
           ]
  end

  test "sees a workflow added after the clone was made, and says when nothing moved",
       %{tmp_dir: tmp_dir} do
    origin =
      git_repository(tmp_dir, %{".github/workflows/build.yml" => workflow(["compile"])})

    repo = %{
      id: unique_repository_id(),
      url: origin,
      branch: "main",
      source_type: "github_actions"
    }

    assert {:ok, [%{path: ".github/workflows/build.yml"}]} = Fetcher.discover(repo)

    commit!(origin, %{".github/workflows/nightly.yml" => workflow(["nightly"])})

    assert {:ok,
            [%{path: ".github/workflows/build.yml"}, %{path: ".github/workflows/nightly.yml"}]} =
             Fetcher.discover(repo)

    assert {:ok, _dir, :unchanged} = Fetcher.fetch(repo)
  end

  test "reads a GitLab CI pipeline as its single file", %{tmp_dir: tmp_dir} do
    origin = git_repository(tmp_dir, %{".gitlab-ci.yml" => gitlab_pipeline(["unit"])})

    repo = %{id: unique_repository_id(), url: origin, branch: "main", source_type: "gitlab_ci"}

    assert {:ok, [%{path: ".gitlab-ci.yml", job_names: ["unit"]}]} = Fetcher.discover(repo)
  end

  test "says why it could not read the repository", %{tmp_dir: tmp_dir} do
    repo = %{
      id: unique_repository_id(),
      url: Path.join(tmp_dir, "no-such-repository"),
      branch: "main",
      source_type: "github_actions"
    }

    assert {:error, reason} = Fetcher.discover(repo)
    assert is_binary(reason)
  end

  # Each test gets its own repository id, and the clone it leaves behind is
  # removed: a clone from an earlier run would point at a directory that no
  # longer exists.
  defp unique_repository_id do
    id = System.unique_integer([:positive, :monotonic])
    on_exit(fn -> File.rm_rf!(Fetcher.repo_dir(%{id: id})) end)
    id
  end

  defp git_repository(tmp_dir, files) do
    dir = Path.join(tmp_dir, "origin-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    git!(dir, ["init", "--quiet"])
    git!(dir, ["checkout", "-b", "main"])
    commit!(dir, files)
    dir
  end

  defp commit!(dir, files) do
    Enum.each(files, fn {path, content} ->
      full = Path.join(dir, path)
      File.mkdir_p!(Path.dirname(full))
      File.write!(full, content)
    end)

    git!(dir, ["add", "."])

    git!(dir, [
      "-c",
      "user.email=test@example.com",
      "-c",
      "user.name=Test",
      "commit",
      "-q",
      "-m",
      "a commit"
    ])
  end

  defp git!(dir, args) do
    case System.cmd("git", ["-C", dir | args], stderr_to_stdout: true) do
      {output, 0} -> output
      {output, status} -> raise "git #{Enum.join(args, " ")} failed (#{status}): #{output}"
    end
  end

  defp workflow(jobs) do
    job_documents =
      Enum.map_join(jobs, "\n", fn job ->
        """
          #{job}:
            runs-on: ubuntu-latest
            steps:
              - run: echo #{job}
        """
      end)

    """
    name: Build
    on: [push]
    jobs:
    #{job_documents}
    """
  end

  # GitLab CI has no `jobs:` wrapper: the top-level keys are the job names.
  defp gitlab_pipeline(jobs) do
    job_documents =
      Enum.map_join(jobs, "\n", fn job ->
        """
        #{job}:
          stage: test
          script:
            - echo #{job}
        """
      end)

    """
    stages: [test]
    #{job_documents}
    """
  end
end
