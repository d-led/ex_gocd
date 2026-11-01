defmodule ExGoCD.ConfigXmlTest do
  use ExGoCD.DataCase

  alias ExGoCD.ConfigRepos.ConfigRepo
  alias ExGoCD.ConfigXml
  alias ExGoCD.Pipelines.Pipeline
  alias ExGoCD.Repo

  describe "from_xml/1" do
    test "parses a simple pipeline from cruise-config.xml" do
      xml = """
      <?xml version="1.0" encoding="utf-8"?>
      <cruise>
        <server serverId="ex-gocd" />
        <pipelines group="default">
          <pipeline name="test-pipeline">
            <params>
              <param name="VERSION">1.0</param>
            </params>
            <timer onlyOnChanges="true">0 0 * * * ?</timer>
            <materials>
              <git url="https://github.com/test/repo.git" branch="main" materialName="test-repo" autoUpdate="true" />
            </materials>
            <environmentvariables>
              <variable name="DEPLOY_ENV">
                <value>staging</value>
              </variable>
              <secureVariable name="SECRET_KEY">
                <encryptedValue>abc123</encryptedValue>
              </secureVariable>
            </environmentvariables>
            <stages>
              <stage name="build" fetchMaterials="true" cleanWorkingDir="false">
                <approval type="success" />
                <jobs>
                  <job name="compile" runInstanceCount="1" timeout="60">
                    <resources>
                      <resource>linux</resource>
                    </resources>
                    <tasks>
                      <exec command="make">
                        <arg>build</arg>
                        <runif status="passed" />
                      </exec>
                    </tasks>
                  </job>
                </jobs>
              </stage>
            </stages>
          </pipeline>
        </pipelines>
      </cruise>
      """

      assert {:ok, [pipeline], _} = ExGoCD.ConfigXml.from_xml(xml)

      assert pipeline.name == "test-pipeline"
      assert pipeline.locked == false
      assert pipeline.timer == "0 0 * * * ?"
      assert pipeline.timer_only_on_changes == true

      assert pipeline.parameters == %{"VERSION" => "1.0"}

      assert [material] = pipeline.materials
      assert material.type == "git"
      assert material.url == "https://github.com/test/repo.git"
      assert material.branch == "main"
      assert material.name == "test-repo"
      assert material.auto_update == true

      assert pipeline.environment_variables == %{
               "DEPLOY_ENV" => %{"value" => "staging", "secure" => false}
             }

      assert pipeline.secure_variables == %{
               "SECRET_KEY" => %{"value" => "abc123", "secure" => true}
             }

      assert [stage] = pipeline.stages
      assert stage.name == "build"
      assert stage.fetch_materials == true
      assert stage.clean_working_directory == false
      assert stage.approval_type == "success"

      assert [job] = stage.jobs
      assert job.name == "compile"
      assert job.run_instance_count == 1
      assert job.timeout == 60
      assert job.resources == ["linux"]

      assert [task] = job.tasks
      assert task.type == "exec"
      assert task.command == "make"
      assert task.args == ["build"]
      assert task.run_if == ["passed"]
    end

    test "parses dependency material" do
      xml = """
      <cruise>
        <pipelines group="default">
          <pipeline name="downstream">
            <materials>
              <pipeline pipelineName="upstream" stageName="build" materialName="upstream-material" />
            </materials>
          </pipeline>
        </pipelines>
      </cruise>
      """

      assert {:ok, [pipeline], _} = ExGoCD.ConfigXml.from_xml(xml)
      assert [material] = pipeline.materials
      assert material.type == "dependency"
      assert material.pipeline_name == "upstream"
      assert material.stage_name == "build"
      assert material.name == "upstream-material"
    end

    test "returns error for invalid XML" do
      assert {:error, _} = ExGoCD.ConfigXml.from_xml("not xml")
    end

    test "returns empty list for XML with no pipelines" do
      xml = "<cruise><server serverId='x'/></cruise>"
      assert {:ok, [], _} = ExGoCD.ConfigXml.from_xml(xml)
    end

    test "parses SVN material with full attributes" do
      xml = """
      <cruise>
        <pipelines group="default">
          <pipeline name="svn-pipeline">
            <materials>
              <svn url="https://svn.example.com/repo/trunk" username="alice" password="secret"
                   checkexternals="true" materialName="my-svn" autoUpdate="true" dest="my-dest" />
            </materials>
          </pipeline>
        </pipelines>
      </cruise>
      """

      assert {:ok, [pipeline], _} = ExGoCD.ConfigXml.from_xml(xml)
      assert [material] = pipeline.materials
      assert material.type == "svn"
      assert material.url == "https://svn.example.com/repo/trunk"
      assert material.username == "alice"
      assert material.name == "my-svn"
      assert material.auto_update == true

      assert material.type_specific_config["check_externals"] == true
      assert material.type_specific_config["password"] == "secret"
    end

    test "parses SVN material without auth (public repo)" do
      xml = """
      <cruise>
        <pipelines group="default">
          <pipeline name="svn-public">
            <materials>
              <svn url="https://svn.apache.org/repos/asf/subversion/trunk"
                   checkexternals="false" materialName="apache-svn" />
            </materials>
          </pipeline>
        </pipelines>
      </cruise>
      """

      assert {:ok, [pipeline], _} = ExGoCD.ConfigXml.from_xml(xml)
      assert [material] = pipeline.materials
      assert material.type == "svn"
      assert material.url == "https://svn.apache.org/repos/asf/subversion/trunk"
      assert material.username == nil
      assert material.type_specific_config["check_externals"] == false
      assert material.type_specific_config["password"] == ""
    end

    test "parses SVN material with username only (cached password)" do
      xml = """
      <cruise>
        <pipelines group="default">
          <pipeline name="svn-cached">
            <materials>
              <svn url="https://svn.example.com/repo" username="bob"
                   checkexternals="false" materialName="bobs-repo" />
            </materials>
          </pipeline>
        </pipelines>
      </cruise>
      """

      assert {:ok, [pipeline], _} = ExGoCD.ConfigXml.from_xml(xml)
      assert [material] = pipeline.materials
      assert material.type == "svn"
      assert material.username == "bob"
      assert material.type_specific_config["password"] == ""
    end
  end

  describe "generate/0" do
    test "renders a git material with its url, branch, destination and name" do
      {:ok, pipeline} =
        ExGoCD.Pipelines.create_pipeline(%{name: "render-git", group: "test-group"})

      ExGoCD.Pipelines.create_material_for_pipeline(pipeline, %{
        type: "git",
        url: "https://github.com/example/repo.git",
        branch: "main",
        name: "repo"
      })

      xml = ExGoCD.ConfigXml.generate()

      assert xml =~ ~s(url="https://github.com/example/repo.git")
      assert xml =~ ~s(branch="main")
      assert xml =~ ~s(dest="repo")
      assert xml =~ ~s(materialName="repo")
    end

    test "renders a dependency material with the pipeline and stage it watches" do
      {:ok, _upstream} =
        ExGoCD.Pipelines.create_pipeline(%{name: "upstream", group: "test-group"})

      {:ok, downstream} =
        ExGoCD.Pipelines.create_pipeline(%{name: "downstream", group: "test-group"})

      ExGoCD.Pipelines.create_material_for_pipeline(downstream, %{
        type: "dependency",
        url: "upstream",
        pipeline_name: "upstream",
        stage_name: "test",
        name: "upstream"
      })

      xml = ExGoCD.ConfigXml.generate()

      assert xml =~ ~s(pipelineName="upstream")
      assert xml =~ ~s(stageName="test")
    end

    test "what it renders parses back into the same material" do
      {:ok, pipeline} =
        ExGoCD.Pipelines.create_pipeline(%{name: "roundtrip", group: "test-group"})

      ExGoCD.Pipelines.create_material_for_pipeline(pipeline, %{
        type: "git",
        url: "https://github.com/example/roundtrip.git",
        branch: "develop",
        name: "roundtrip"
      })

      assert {:ok, pipelines, _} = ExGoCD.ConfigXml.from_xml(ExGoCD.ConfigXml.generate())

      roundtrip = Enum.find(pipelines, &(&1.name == "roundtrip"))

      assert [material] = roundtrip.materials
      assert material.type == "git"
      assert material.url == "https://github.com/example/roundtrip.git"
      assert material.branch == "develop"
      assert material.name == "roundtrip"
    end

    test "renders a template with the stages and jobs it declares" do
      {:ok, template} = ExGoCD.Pipelines.create_template(%{name: "shared-build"})
      {:ok, stage} = ExGoCD.Pipelines.create_stage(%{name: "build", template_id: template.id})
      {:ok, _job} = ExGoCD.Pipelines.create_job(%{name: "compile", stage_id: stage.id})

      xml = ExGoCD.ConfigXml.generate()

      assert xml =~ ~s(<pipeline name="shared-build" template="true")
      assert xml =~ ~s(<stage name="build")
      assert xml =~ ~s(<job name="compile")
    end

    test "renders an environment with the pipelines assigned to it" do
      {:ok, _pipeline} = ExGoCD.Pipelines.create_pipeline(%{name: "deploy", group: "test"})
      {:ok, _env} = ExGoCD.Environments.create_environment(%{name: "staging"})
      ExGoCD.Environments.add_pipeline_to_environment("staging", "deploy")

      xml = ExGoCD.ConfigXml.generate()

      assert xml =~ ~s(<environment name="staging")
      assert xml =~ ~s(<pipeline name="deploy")
    end

    test "renders security roles and elastic agent profiles" do
      {:ok, _role} =
        ExGoCD.Accounts.create_role(%{name: "deployers", users: ["alice"], policy: %{}})

      {:ok, cluster} =
        ExGoCD.ClusterProfiles.create_profile(%{
          name: "k8s",
          plugin_id: "ex_gocd.elasticagent.kubernetes",
          properties: %{}
        })

      {:ok, _profile} =
        ExGoCD.ElasticAgentProfiles.create_profile(%{
          name: "small",
          plugin_id: "ex_gocd.elasticagent.kubernetes",
          cluster_profile_id: cluster.id,
          properties: %{"MaxCPU" => "2"}
        })

      xml = ExGoCD.ConfigXml.generate()

      assert xml =~ ~s(<role name="deployers")
      assert xml =~ ~s(<user name="alice")
      assert xml =~ ~s(<agentProfile name="small")
      assert xml =~ "MaxCPU"
    end
  end

  describe "cluster profiles" do
    test "a cluster profile and the agent profile using it survive a round trip" do
      {:ok, cluster} =
        ExGoCD.ClusterProfiles.create_profile(%{
          name: "k8s",
          plugin_id: "ex_gocd.elasticagent.kubernetes",
          properties: %{
            "kubernetes_cluster_url" => "https://k8s.test:6443",
            "bearer_token" => "a-bearer-token"
          }
        })

      {:ok, agent_profile} =
        ExGoCD.ElasticAgentProfiles.create_profile(%{
          name: "small",
          plugin_id: "ex_gocd.elasticagent.kubernetes",
          cluster_profile_id: cluster.id,
          properties: %{"MaxCPU" => "2"}
        })

      xml = ExGoCD.ConfigXml.generate()

      assert xml =~ ~s(<clusterProfile name="k8s")
      assert xml =~ ~s(clusterProfileId="k8s")
      refute xml =~ "a-bearer-token"

      # Empty the database the way a revert would, then import the export.
      {:ok, _} = ExGoCD.ElasticAgentProfiles.delete_profile(agent_profile)
      {:ok, _} = ExGoCD.ClusterProfiles.delete_profile(cluster)

      assert {:ok, _counts} = ExGoCD.ConfigXml.import_from_xml(xml)

      assert [restored] = ExGoCD.ClusterProfiles.list_profiles()
      assert restored.name == "k8s"

      assert ExGoCD.ClusterProfiles.ClusterProfile.bearer_token(restored) ==
               "a-bearer-token"

      assert [agent] = ExGoCD.ElasticAgentProfiles.list_profiles()
      assert agent.cluster_profile_id == restored.id
    end
  end

  describe "import_from_xml/1" do
    test "stores the material, stage, job and task the XML declares" do
      assert {:ok, %{pipelines: 1}} = ExGoCD.ConfigXml.import_from_xml(cruise_xml("imported"))

      pipeline = load_pipeline("imported")

      assert [material] = pipeline.materials
      assert material.type == "git"
      assert material.url == "https://github.com/example/imported.git"
      assert material.branch == "main"

      assert [stage] = pipeline.stages
      assert stage.name == "build"

      assert [job] = stage.jobs
      assert job.name == "compile"

      assert [task] = job.tasks
      assert task.command == "make"
      assert task.arguments == ["build"]
    end

    test "importing the same XML twice leaves one stage and one job" do
      assert {:ok, _} = ExGoCD.ConfigXml.import_from_xml(cruise_xml("imported"))
      assert {:ok, _} = ExGoCD.ConfigXml.import_from_xml(cruise_xml("imported"))

      assert [stage] = load_pipeline("imported").stages
      assert [job] = stage.jobs
      assert job.name == "compile"
    end

    test "reports a pipeline it cannot store instead of counting it as imported" do
      xml = cruise_xml("not a valid pipeline name")

      assert {:error, message} = ExGoCD.ConfigXml.import_from_xml(xml)
      assert message =~ "not a valid pipeline name"
      assert ExGoCD.Pipelines.get_pipeline_by_name("not a valid pipeline name") == nil
    end

    test "a dependency material is stored once its upstream pipeline exists" do
      xml = """
      <cruise>
        <pipelines group="default">
          <pipeline name="downstream">
            <materials>
              <pipeline pipelineName="upstream" stageName="build" materialName="upstream"/>
            </materials>
          </pipeline>
          <pipeline name="upstream"/>
        </pipelines>
      </cruise>
      """

      assert {:ok, %{pipelines: 2}} = ExGoCD.ConfigXml.import_from_xml(xml)

      assert [material] = load_pipeline("downstream").materials
      assert material.type == "dependency"
      assert material.url == "upstream"
    end

    defp cruise_xml(pipeline_name) do
      """
      <cruise>
        <pipelines group="default">
          <pipeline name="#{pipeline_name}">
            <materials>
              <git url="https://github.com/example/imported.git" branch="main" materialName="imported"/>
            </materials>
            <stages>
              <stage name="build">
                <jobs>
                  <job name="compile">
                    <tasks>
                      <exec command="make"><arg>build</arg></exec>
                    </tasks>
                  </job>
                </jobs>
              </stage>
            </stages>
          </pipeline>
        </pipelines>
      </cruise>
      """
    end

    defp load_pipeline(name) do
      ExGoCD.Pipelines.get_pipeline_by_name(name)
      |> Repo.preload([:materials, stages: [jobs: :tasks]])
    end
  end

  describe "config repos" do
    test "exports the repository and leaves its pipelines to the repository" do
      config_repo = insert_config_repo()
      insert_pipeline(name: "hand-written")
      insert_pipeline(name: "from-the-repository", config_repo_id: config_repo.id)

      xml = ConfigXml.generate()

      assert xml =~ ~s(<config-repo pluginId="cd.go.config-repo.yaml")
      assert xml =~ ~s(url="https://github.com/acme/config.git")
      assert xml =~ ~s(branch="trunk")
      assert xml =~ "hand-written"
      refute xml =~ "from-the-repository"
    end

    test "importing stores the repository again" do
      xml = """
      <?xml version="1.0" encoding="utf-8"?>
      <cruise schemaVersion="120">
        <config-repos>
          <config-repo pluginId="cd.go.config-repo.yaml" materialType="git" sourceType="gocd_pipeline">
            <git url="https://github.com/acme/config.git" branch="trunk" />
            <configuration>
              <property><key>pattern</key><value>*.gocd.yaml</value></property>
            </configuration>
          </config-repo>
        </config-repos>
      </cruise>
      """

      assert {:ok, _summary} = ConfigXml.import_from_xml(xml)

      assert [imported] = Repo.all(ConfigRepo)
      assert imported.url == "https://github.com/acme/config.git"
      assert imported.branch == "trunk"
      assert imported.plugin_id == "cd.go.config-repo.yaml"
      assert imported.configuration == %{"pattern" => "*.gocd.yaml"}
    end

    test "a generated document imports back to the same repository" do
      insert_config_repo()

      assert {:ok, %{config_repos: 1}} = ConfigXml.import_from_xml(ConfigXml.generate())

      assert [imported] = Repo.all(ConfigRepo)
      assert imported.url == "https://github.com/acme/config.git"
      assert imported.branch == "trunk"
      assert imported.configuration == %{"pattern" => "*.gocd.yaml"}
    end

    defp insert_config_repo do
      Repo.insert!(%ConfigRepo{
        url: "https://github.com/acme/config.git",
        branch: "trunk",
        plugin_id: "cd.go.config-repo.yaml",
        configuration: %{"pattern" => "*.gocd.yaml"}
      })
    end

    defp insert_pipeline(attrs) do
      Repo.insert!(struct(Pipeline, attrs))
    end
  end
end
