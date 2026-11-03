defmodule ExGoCD.GitRepository do
  @moduledoc """
  A real git repository in a temporary directory, for the tests that read one:
  a configuration repository is a clone of something, and the thing it clones can
  be a local mirror — or this.

  Created under a directory the test owns, so `tmp_dir` from `@moduletag :tmp_dir`
  decides where it lives and when it goes.
  """

  @doc """
  Creates a repository holding `files` (path → content) and answers its path.
  """
  def create(dir, files) do
    File.mkdir_p!(dir)

    Enum.each(files, fn {path, content} ->
      full = Path.join(dir, path)
      File.mkdir_p!(Path.dirname(full))
      File.write!(full, content)
    end)

    git!(dir, ["init", "--quiet"])
    git!(dir, ["checkout", "-b", "main"])
    git!(dir, ["add", "."])

    git!(dir, [
      "-c",
      "user.email=test@example.com",
      "-c",
      "user.name=Test",
      "commit",
      "-q",
      "-m",
      "initial"
    ])

    dir
  end

  @doc "A GitHub Actions workflow defining `jobs`."
  def github_workflow(jobs) do
    documents =
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
    #{documents}
    """
  end

  # GitLab CI has no `jobs:` wrapper: the top-level keys are the job names.
  @doc "A GitLab CI pipeline defining `jobs`."
  def gitlab_pipeline(jobs) do
    documents =
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
    #{documents}
    """
  end

  defp git!(dir, args) do
    case System.cmd("git", ["-C", dir | args], stderr_to_stdout: true) do
      {output, 0} -> output
      {output, status} -> raise "git #{Enum.join(args, " ")} failed (#{status}): #{output}"
    end
  end
end
