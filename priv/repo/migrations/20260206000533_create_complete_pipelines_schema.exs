defmodule ExGoCD.Repo.Migrations.CreateCompletePipelinesSchema do
  use Ecto.Migration

  def change do
    # Materials - triggers for pipelines (Git, SVN, dependency, etc.)
    # Based on: domain/materials/Material.java interface + implementations
    create table(:materials) do
      add :type, :string, null: false
      add :url, :string
      add :branch, :string
      add :username, :string
      add :destination, :string
      add :auto_update, :boolean, default: true, null: false
      add :filter_ignore, {:array, :string}, default: []
      add :filter_include, {:array, :string}, default: []

      # Type-specific fields stored as JSONB for polymorphism
      # Git: shallow_clone, submodule_folder
      # SVN: check_externals, password (encrypted)
      # Dependency: pipeline_name, stage_name
      # Package/PluggableSCM: package_id, scm_id
      add :type_specific_config, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:materials, [:type])

    # Pipelines - configuration/definition (PipelineConfig in GoCD)
    # Based on: config/config-api/.../PipelineConfig.java
    create table(:pipelines) do
      add :name, :string, null: false
      add :group, :string
      add :label_template, :string, default: "${COUNT}"
      add :lock_behavior, :string, default: "none"
      add :environment_variables, :map, default: %{}
      add :timer, :string

      # Additional fields from PipelineConfig
      add :params, :map, default: %{}
      add :tracking_tool, :map
      add :template_name, :string
      add :display_order_weight, :integer, default: -1

      timestamps(type: :utc_datetime)
    end

    create unique_index(:pipelines, [:name])
    create index(:pipelines, [:group])

    # Join table for pipeline-material many-to-many relationship
    create table(:pipelines_materials, primary_key: false) do
      add :pipeline_id, references(:pipelines, on_delete: :delete_all), null: false
      add :material_id, references(:materials, on_delete: :delete_all), null: false
    end

    create index(:pipelines_materials, [:pipeline_id])
    create index(:pipelines_materials, [:material_id])
    create unique_index(:pipelines_materials, [:pipeline_id, :material_id])

    # Stages - configuration/definition within pipeline (StageConfig in GoCD)
    # Based on: config/config-api/.../StageConfig.java
    create table(:stages) do
      add :name, :string, null: false
      add :fetch_materials, :boolean, default: true, null: false
      add :never_cleanup_artifacts, :boolean, default: false, null: false
      add :clean_working_directory, :boolean, default: false, null: false
      add :approval_type, :string, default: "success", null: false
      add :environment_variables, :map, default: %{}

      # Note: GoCD has full Approval object with authorization (users/roles)
      # For now storing as simple type, can expand to JSONB later
      add :approval_authorization, :map, default: %{}

      add :pipeline_id, references(:pipelines, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:stages, [:pipeline_id])
    create unique_index(:stages, [:pipeline_id, :name])

    # Jobs - configuration/definition within stage (JobConfig in GoCD)
    # Based on: config/config-api/.../JobConfig.java
    create table(:jobs) do
      add :name, :string, null: false
      add :resources, {:array, :string}, default: []
      add :environment_variables, :map, default: %{}
      # "never" or numeric value as string
      add :timeout, :string
      add :run_instance_count, :string
      add :run_on_all_agents, :boolean, default: false, null: false
      add :elastic_profile_id, :string

      # Additional fields from JobConfig
      add :tabs, :map, default: %{}
      add :artifact_configs, :map, default: %{}

      add :stage_id, references(:stages, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:jobs, [:stage_id])
    create unique_index(:jobs, [:stage_id, :name])

    # Tasks - configuration/definition within job (Task interface + implementations)
    # Based on: config/config-api/.../ExecTask.java, AntTask.java, etc.
    create table(:tasks) do
      add :type, :string, null: false
      add :command, :string
      add :arguments, {:array, :string}, default: []
      add :working_directory, :string
      add :run_if, :string, default: "passed", null: false
      # -1 or nil for no timeout
      add :timeout, :integer
      add :on_cancel, :map

      add :job_id, references(:jobs, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:tasks, [:job_id])

    # Pipeline Instances - execution tracking (Pipeline in GoCD domain)
    # Based on: domain/Pipeline.java
    create table(:pipeline_instances) do
      add :counter, :integer, null: false
      add :label, :string, null: false
      add :natural_order, :float, null: false

      # BuildCause - what triggered this run
      # BuildCause has: MaterialRevisions, approver, message, etc.
      add :build_cause, :map, null: false

      add :pipeline_id, references(:pipelines, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:pipeline_instances, [:pipeline_id])
    create index(:pipeline_instances, [:counter])
    create unique_index(:pipeline_instances, [:pipeline_id, :counter])

    # Stage Instances - execution tracking within pipeline instance (Stage in GoCD domain)
    # Based on: domain/Stage.java
    create table(:stage_instances) do
      add :name, :string, null: false
      add :counter, :integer, null: false
      add :order_id, :integer, null: false
      # StageState enum
      add :state, :string, null: false
      # StageResult enum
      add :result, :string, default: "Unknown", null: false
      add :approval_type, :string, null: false
      add :approved_by, :string
      add :cancelled_by, :string

      # Timing
      add :created_time, :utc_datetime, null: false
      add :last_transitioned_time, :utc_datetime
      add :scheduled_at, :naive_datetime
      add :completed_at, :naive_datetime

      # Config fields copied to instance
      add :fetch_materials, :boolean, default: true, null: false
      add :clean_working_dir, :boolean, default: false, null: false

      # Tracking fields
      # Full StageIdentifier string
      add :identifier, :string
      add :completed_by_transition_id, :bigint
      add :latest_run, :boolean, default: true, null: false
      add :rerun_of_counter, :integer
      add :artifacts_deleted, :boolean, default: false, null: false
      add :config_version, :string

      add :pipeline_instance_id, references(:pipeline_instances, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:stage_instances, [:pipeline_instance_id])
    create index(:stage_instances, [:state])
    create index(:stage_instances, [:result])
    create unique_index(:stage_instances, [:pipeline_instance_id, :name, :counter])

    # Job Instances - execution tracking within stage instance (JobInstance in GoCD domain)
    # Based on: domain/JobInstance.java
    create table(:job_instances) do
      add :name, :string, null: false
      # JobState enum
      add :state, :string, default: "Scheduled", null: false
      # JobResult enum
      add :result, :string, default: "Unknown", null: false
      add :agent_uuid, :string

      # Timing
      add :scheduled_at, :naive_datetime, null: false
      add :assigned_at, :naive_datetime
      add :completed_at, :naive_datetime

      # Config flags copied to instance
      add :run_on_all_agents, :boolean, default: false, null: false
      add :run_multiple_instance, :boolean, default: false, null: false

      # Tracking fields
      add :ignored, :boolean, default: false, null: false
      # Full JobIdentifier string
      add :identifier, :string
      add :original_job_id, :bigint
      add :rerun, :boolean, default: false, null: false

      add :stage_instance_id, references(:stage_instances, on_delete: :delete_all), null: false
      # Link back to config
      add :job_id, references(:jobs, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:job_instances, [:stage_instance_id])
    create index(:job_instances, [:job_id])
    create index(:job_instances, [:state])
    create index(:job_instances, [:result])
    create index(:job_instances, [:agent_uuid])
  end
end
