defmodule ExGoCD.ConfigXmlTest do
  use ExGoCD.DataCase

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

      assert {:ok, [pipeline]} = ExGoCD.ConfigXml.from_xml(xml)

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

      assert {:ok, [pipeline]} = ExGoCD.ConfigXml.from_xml(xml)
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
      assert {:ok, []} = ExGoCD.ConfigXml.from_xml(xml)
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

      assert {:ok, [pipeline]} = ExGoCD.ConfigXml.from_xml(xml)
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

      assert {:ok, [pipeline]} = ExGoCD.ConfigXml.from_xml(xml)
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

      assert {:ok, [pipeline]} = ExGoCD.ConfigXml.from_xml(xml)
      assert [material] = pipeline.materials
      assert material.type == "svn"
      assert material.username == "bob"
      assert material.type_specific_config["password"] == ""
    end
  end
end
