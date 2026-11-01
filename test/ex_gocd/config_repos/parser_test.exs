defmodule ExGoCD.ConfigRepos.ParserTest do
  use ExGoCD.DataCase, async: true

  alias ExGoCD.ConfigRepos
  alias ExGoCD.ConfigRepos.Parser
  alias ExGoCD.Pipelines

  describe "parse_and_upsert/2" do
    test "stores the pipelines the file declares" do
      assert {:ok, 2} = Parser.parse_and_upsert(pipelines_yaml(~w(one two)), nil)

      assert Pipelines.get_pipeline_by_name("one")
      assert Pipelines.get_pipeline_by_name("two")
    end

    test "stores the group the declaration names" do
      yaml = """
      pipelines:
        deploy:
          group: production
      """

      assert {:ok, 1} = Parser.parse_and_upsert(yaml, nil)

      assert Pipelines.get_pipeline_by_name("deploy").group == "production"
    end

    test "removes a pipeline the repository no longer declares" do
      repo = insert_repo()

      assert {:ok, 2} = Parser.parse_and_upsert(pipelines_yaml(~w(one two)), repo.id)
      assert {:ok, 1} = Parser.parse_and_upsert(pipelines_yaml(~w(one)), repo.id)

      assert Pipelines.get_pipeline_by_name("one")
      assert Pipelines.get_pipeline_by_name("two") == nil
    end

    test "keeps the last good config when the content cannot be parsed" do
      repo = insert_repo()

      assert {:ok, 2} = Parser.parse_and_upsert(pipelines_yaml(~w(one two)), repo.id)
      assert {:error, _reason} = Parser.parse_and_upsert("pipelines: [unclosed", repo.id)

      assert Pipelines.get_pipeline_by_name("one")
      assert Pipelines.get_pipeline_by_name("two")
    end

    test "keeps the last good config when the file declares no pipelines" do
      repo = insert_repo()

      assert {:ok, 1} = Parser.parse_and_upsert(pipelines_yaml(~w(one)), repo.id)
      assert {:error, _reason} = Parser.parse_and_upsert("pipelines: {}\n", repo.id)

      assert Pipelines.get_pipeline_by_name("one")
    end

    test "leaves pipelines belonging to another repository alone" do
      mine = insert_repo("https://github.com/example/mine.git")
      theirs = insert_repo("https://github.com/example/theirs.git")

      assert {:ok, 1} = Parser.parse_and_upsert(pipelines_yaml(~w(theirs)), theirs.id)
      assert {:ok, 1} = Parser.parse_and_upsert(pipelines_yaml(~w(mine)), mine.id)
      assert {:ok, 1} = Parser.parse_and_upsert(pipelines_yaml(~w(mine)), mine.id)

      assert Pipelines.get_pipeline_by_name("theirs")
    end

    test "leaves pipelines that no repository owns alone" do
      repo = insert_repo()

      assert {:ok, 1} = Parser.parse_and_upsert(pipelines_yaml(~w(handmade)), nil)
      assert {:ok, 1} = Parser.parse_and_upsert(pipelines_yaml(~w(from-repo)), repo.id)
      assert {:ok, 1} = Parser.parse_and_upsert(pipelines_yaml(~w(from-repo)), repo.id)

      assert Pipelines.get_pipeline_by_name("handmade")
    end
  end

  defp pipelines_yaml(names) do
    declarations =
      Enum.map_join(names, "", fn name -> "  #{name}:\n    group: default\n" end)

    "pipelines:\n" <> declarations
  end

  defp insert_repo(url \\ "https://github.com/example/repo.git") do
    {:ok, repo} = ConfigRepos.create_config_repo(%{url: url, source_type: "gocd_pipeline"})
    repo
  end
end
