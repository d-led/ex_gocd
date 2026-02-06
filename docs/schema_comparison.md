# Schema Comparison: GoCD Java → Phoenix Elixir

## Summary

Current schemas mix configuration and instance concepts. GoCD separates:
- **Config classes** (PipelineConfig, StageConfig, JobConfig) - Define what to run
- **Instance classes** (Pipeline, Stage, JobInstance) - Track execution

Our schemas follow the same pattern:
- Pipeline, Stage, Job, Task - CONFIG/DEFINITION ✅
- PipelineInstance, StageInstance, JobInstance - EXECUTION TRACKING ✅

**BUT** - field mappings are incomplete and sometimes incorrect.

---

## 1. Pipeline (Config) Schema

### GoCD Source: `PipelineConfig.java`

```java
// config/config-api/.../PipelineConfig.java
private CaseInsensitiveString name;                    // REQUIRED
private String labelTemplate;                          // Default: "${COUNT}"
private ParamsConfig params;                           // Pipeline parameters
private TrackingTool trackingTool;                     // Issue tracker integration
private TimerConfig timer;                             // Cron-like timer
private EnvironmentVariablesConfig variables;          // Environment variables
private MaterialConfigs materialConfigs;               // Collection ofmaterials
private String lockBehavior;                           // "none", "lockOnFailure", "unlockWhenFinished"
private CaseInsensitiveString templateName;            // Template reference (optional)
private ConfigOrigin origin;                           // Where config comes from (file/repo)
private int displayOrderWeight;                        // UI display order
private boolean templateApplied;                       // Whether template is applied
// extends BaseCollection<StageConfig> - has list of stages
```

### Phoenix Schema: `lib/ex_gocd/pipelines/pipeline.ex`

```elixir
field :name, :string                          # ✅ MATCHES (name)
field :group, :string                         # ✅ CORRECT (pipeline group name)  
field :label_template, :string                # ✅ MATCHES (labelTemplate)
field :lock_behavior, :string                 # ✅ MATCHES (lockBehavior)
field :environment_variables, :map            # ✅ MATCHES (variables)
field :timer, :string                         # ✅ SIMPLIFIED (TimerConfig → cron string)

has_many :stages, Stage                       # ✅ MATCHES (extends BaseCollection<StageConfig>)
many_to_many :materials, Material             # ✅ MATCHES (materialConfigs)
has_many :instances, PipelineInstance         # ✅ CORRECT (instances of this pipeline)
```

### Missing Fields

- ❌ `params` - pipeline parameters (ParamsConfig)
- ❌ `tracking_tool` - issue tracker config (TrackingTool)
- ❌ `template_name` - template reference
- ❌ `display_order_weight` - UI ordering
- ❌ `origin` - config source (file/repo) - maybe not needed for MVP

### Field Issues

- ⚠️ `timer` - simplified to string, GoCD uses TimerConfig object with spec + onlyOnChanges flag

---

## 2. Stage (Config) Schema

### GoCD Source: `StageConfig.java`

```java
// config/config-api/.../StageConfig.java
private CaseInsensitiveString name;                    // REQUIRED
private boolean fetchMaterials;                        // Default: true
private boolean artifactCleanupProhibited;             // Default: false (called "never_cleanup_artifacts" in our schema)
private boolean cleanWorkingDir;                       // Default: false
private Approval approval;                             // Approval config (type + authorization)
private EnvironmentVariablesConfig variables;          // Environment variables
private JobConfigs jobConfigs;                         // Collection of jobs
```

### Phoenix Schema: `lib/ex_gocd/pipelines/stage.ex`

```elixir
field :name, :string                          # ✅ MATCHES (name)
field :fetch_materials, :boolean              # ✅ MATCHES (fetchMaterials)
field :clean_working_directory, :boolean      # ✅ MATCHES (cleanWorkingDir)
field :never_cleanup_artifacts, :boolean      # ✅ MATCHES (artifactCleanupProhibited)
field :approval_type, :string                 # ⚠️ SIMPLIFIED (Approval object → string)
field :environment_variables, :map            # ✅ MATCHES (variables)

belongs_to :pipeline, Pipeline                # ✅ CORRECT (parent pipeline config)
has_many :jobs, Job                           # ✅ MATCHES (jobConfigs)
```

### Missing Fields

- ❌ Approval authorization (who can approve) - Approval object has more than just type

### Field Issues

- ⚠️ `approval_type` - GoCD has full Approval object with type + authorization (users/roles who can approve)

---

## 3. Job (Config) Schema

### GoCD Source: `JobConfig.java`

```java
// config/config-api/.../JobConfig.java
private CaseInsensitiveString jobName;                 // REQUIRED
private EnvironmentVariablesConfig variables;          // Environment variables
private Tasks tasks;                                   // Collection of tasks
private Tabs tabs;                                     // Custom tabs for job console
private ResourceConfigs resourceConfigs;               // Required resources
private ArtifactTypeConfigs artifactTypeConfigs;       // Artifact publishing config
private boolean runOnAllAgents;                        // Run on all agents flag
private String runInstanceCount;                       // Number of instances (or "all")
private String timeout;                                // Timeout (string for "never" or number)
private String elasticProfileId;                       // Elastic agent profile
```

### Phoenix Schema: `lib/ex_gocd/pipelines/job.ex`

```elixir
field :name, :string                          # ✅ MATCHES (jobName)
field :run_instance_count, :string            # ✅ MATCHES (runInstanceCount)
field :timeout, :integer                      # ⚠️ WRONG TYPE (should be string for "never")
field :resources, {:array, :string}           # ✅ MATCHES (resourceConfigs)
field :environment_variables, :map            # ✅ MATCHES (variables)

belongs_to :stage, Stage                      # ✅ CORRECT (parent stage config)
has_many :tasks, Task                         # ✅ MATCHES (tasks)
```

### Missing Fields

- ❌ `tabs` - custom tabs configuration
- ❌ `artifact_configs` - artifact publishing (critical feature!)
- ❌ `run_on_all_agents` - boolean flag
- ❌ `elastic_profile_id` - elastic agent profile

### Field Issues

- ❌ `timeout` - should be `:string` not `:integer` (GoCD allows "never" or timeout value)

---

## 4. Task (Config) Schema

### GoCD Source: `ExecTask.java` (example implementation)

```java
// config/config-api/.../ExecTask.java (implements Task interface)
private String command;                                // Command to execute
private String args;                                   // Arguments (deprecated)
private String workingDirectory;                       // Working directory
private Long timeout;                                  // Timeout (-1 for none)
private Arguments argList;                             // Proper arguments list
// Inherited from AbstractTask:
private RunIfConfigs conditions;                       // When to run (passed/failed/any)
private Task cancelTask;                               // Task to run on cancel
```

### Phoenix Schema: `lib/ex_gocd/pipelines/task.ex`

```elixir
field :type, :string                          # ✅ CORRECT (task type)
field :command, :string                       # ✅ MATCHES (command)
field :arguments, {:array, :string}           # ✅ MATCHES (argList)
field :working_directory, :string             # ✅ MATCHES (workingDirectory)
field :run_if, :string                        # ✅ MATCHES (conditions)
field :timeout, :integer                      # ⚠️ SHOULD ALLOW NULL (-1 or nil)
field :on_cancel, :map                        # ✅ SIMPLIFIED (cancelTask → map)

belongs_to :job, Job                          # ✅ CORRECT (tasks belong to job config)
```

### Missing Fields

- None for basic exec task!

### Field Issues

- ⚠️ `timeout` - should allow nil/-1 for "no timeout"
- ⚠️ Different task types (ant, rake, nant, fetch) have different fields - need polymorphic handling

---

## 5. Material (Config) Schema

### GoCD Source: Material interface + implementations

```java
// domain/materials/Material.java (interface)
// Multiple implementations:
// - GitMaterial: url, branch, submoduleFolders, shallowClone
// - SvnMaterial: url, username, password, checkExternals
// - HgMaterial: url, branch
// - P4Material: serverAndPort, username, password, view, useTickets
// - TfsMaterial: url, projectPath, domain, username, password
// - DependencyMaterial: pipelineName, stageName
// - PackageMaterial: packageId
// - PluggableSCMMaterial: scmId

// Common fields:
String folder/destination;                             // Where to checkout
boolean autoUpdate;                                    // Poll for changes
Filter filter;                                         // Path patterns to ignore/include
```

### Phoenix Schema: `lib/ex_gocd/pipelines/material.ex`

```elixir
field :type, :string                          # ✅ CORRECT (material type)
field :url, :string                           # ✅ MATCHES (for SCM materials)
field :branch, :string                        # ✅ MATCHES (git/hg)
field :username, :string                      # ✅ MATCHES (auth)
field :destination, :string                   # ✅ MATCHES (folder)
field :auto_update, :boolean                  # ✅ MATCHES (autoUpdate)
field :filter_ignore, {:array, :string}       # ✅ MATCHES (filter ignore patterns)
field :filter_include, {:array, :string}      # ✅ MATCHES (filter include patterns)

many_to_many :pipelines, Pipeline             # ✅ CORRECT (materials → pipelines)
```

### Missing Fields (per material type)

Git:
- ❌ `shallow_clone` - boolean
- ❌ `submodule_folder` - string

SVN:
- ❌ `check_externals` - boolean
- ❌ `password` - encrypted

P4/TFS:
- ❌ Many specific fields

Dependency:
- ❌ `pipeline_name` - string
- ❌ `stage_name` - string

Package/PluggableSCM:
- ❌ `package_id` / `scm_id` - references

### Approach

Polymorphic with type-specific fields stored in :map for MVP, or create separate schemas per type.

---

## 6. PipelineInstance (Execution) Schema

### GoCD Source: `Pipeline.java` (domain)

```java
// domain/Pipeline.java - THIS IS THE INSTANCE!
private String pipelineName;                           // Name from config
private int counter;                                   // Incrementing run number
private PipelineLabel pipelineLabel;                   // Display label (e.g., "1.2.3")
private Stages stages;                                 // Collection of Stage instances
private BuildCause buildCause;                         // What triggered this
private double naturalOrder;                           // For display ordering
// Inherits from PersistentObject:
private Long id;
```

### Phoenix Schema: `lib/ex_gocd/pipelines/pipeline_instance.ex`

```elixir
field :counter, :integer                      # ✅ MATCHES (counter)
field :label, :string                         # ✅ MATCHES (pipelineLabel.toString())
field :status, :string                        # ⚠️ NOT IN JAVA (computed from stages)
field :triggered_by, :string                  # ⚠️ SIMPLIFIED (buildCause.approver)
field :trigger_message, :string               # ⚠️ SIMPLIFIED (buildCause.message)
field :natural_order, :float                  # ✅ MATCHES (naturalOrder)
field :scheduled_at, :naive_datetime          # ⚠️ NOT EXPLICIT (from first stage createdTime)
field :completed_at, :naive_datetime          # ⚠️ NOT EXPLICIT (from last stage completedTime)

belongs_to :pipeline, Pipeline                # ✅ CORRECT (references config)
has_many :stage_instances, StageInstance      # ✅ MATCHES (stages collection)
```

### Missing Fields

- ❌ `build_cause` - full BuildCause object (materials, trigger reason, etc.)
- ❌ GoCD doesn't store status/scheduled_at/completed_at at pipeline level - computed from stages!

### Field Issues

- ❌ `status` - not in GoCD, computed from stage states
- ❌ `triggered_by` + `trigger_message` - oversimplified, should be BuildCause
- ⚠️ `scheduled_at` / `completed_at` - GoCD computes these from stages, we're duplicating

---

## 7. StageInstance (Execution) Schema

### GoCD Source: `Stage.java` (domain)

```java
// domain/Stage.java - THIS IS THE INSTANCE!
private Long pipelineId;                               // Parent pipeline instance
private String name;                                   // Name from config
private JobInstances jobInstances;                     // Collection of job instances
private String approvedBy;                             // Who approved
private String cancelledBy;                            // Who cancelled
private int orderId;                                   // Order within pipeline
private Timestamp createdTime;                         // When created
private Timestamp lastTransitionedTime;                // Last state change
private String approvalType;                           // "success" or "manual"
private boolean fetchMaterials;                        // From config
private StageResult result;                            // Unknown/Passed/Failed/Cancelled
private int counter;                                   // Stage run counter (for reruns)
private StageIdentifier identifier;                    // Full identifier
private Long completedByTransitionId;                  // Transition that completed
private StageState state;                              // Building/Passed/Failed/etc
private boolean latestRun;                             // Is this the latest?
private boolean cleanWorkingDir;                       // From config
private Integer rerunOfCounter;                        // If rerun, original counter
private boolean artifactsDeleted;                      // Cleanup flag
private String configVersion;                          // Config version hash
private StageIdentifier previousStage;                 // Previous stage ref
// Inherits from PersistentObject:
private Long id;
```

### Phoenix Schema: `lib/ex_gocd/pipelines/stage_instance.ex`

```elixir
field :name, :string                          # ✅ MATCHES (name)
field :counter, :integer                      # ✅ MATCHES (counter)
field :state, :string                         # ✅ MATCHES (state)
field :result, :string                        # ✅ MATCHES (result)
field :approved_by, :string                   # ✅ MATCHES (approvedBy)
field :cancelled_by, :string                  # ✅ MATCHES (cancelledBy)
field :approval_type, :string                 # ✅ MATCHES (approvalType)
field :scheduled_at, :naive_datetime          # ⚠️ MATCHES (createdTime)
field :completed_at, :naive_datetime          # ⚠️ COMPUTED (from lastTransitionedTime)

belongs_to :pipeline_instance, PipelineInstance  # ✅ MATCHES (pipelineId)
has_many :job_instances, JobInstance          # ✅ MATCHES (jobInstances)
```

### Missing Fields

- ❌ `order_id` - order within pipeline
- ❌ `last_transitioned_time` - when last state change happened
- ❌ `fetch_materials` - copied from config
- ❌ `identifier` - StageIdentifier (pipeline/counter/stage/counter)
- ❌ `completed_by_transition_id` - internal tracking
- ❌ `latest_run` - boolean flag
- ❌ `clean_working_dir` - copied from config
- ❌ `rerun_of_counter` - for stage reruns
- ❌ `artifacts_deleted` - cleanup tracking
- ❌ `config_version` - config hash at run time
- ❌ `previous_stage` - reference to previous stage

### Field Issues

- ⚠️ Many config fields (fetch_materials, clean_working_dir, approval_type) are DUPLICATED from StageConfig to Stage instance in GoCD
- ⚠️ Missing rerun tracking (rerun_of_counter, latest_run)

---

## 8. JobInstance (Execution) Schema

### GoCD Source: `JobInstance.java` (domain)

```java
// domain/JobInstance.java
private long stageId;                                  // Parent stage instance
private String name;                                   // Job name from config
private JobState state;                                // Scheduled/Assigned/Building/Completed/etc
private JobResult result;                              // Unknown/Passed/Failed/Cancelled
private String agentUuid;                              // Agent running this
private JobStateTransitions stateTransitions;          // State change history (not persisted separately)
private Date scheduledDate;                            // When scheduled
private boolean ignored;                               // Ignore flag
private JobIdentifier identifier;                      // Full identifier
private boolean runOnAllAgents;                        // From config
private boolean runMultipleInstance;                   // From config
private Long originalJobId;                            // For reruns
private boolean rerun;                                 // Is this a rerun?
private boolean pipelineStillConfigured;               // Is pipeline still in config?
private JobPlan plan;                                  // Not persisted here
// Inherits from PersistentObject:
private Long id;
```

### Phoenix Schema: `lib/ex_gocd/pipelines/job_instance.ex`

```elixir
field :name, :string                          # ✅ MATCHES (name)
field :state, :string                         # ✅ MATCHES (state)
field :result, :string                        # ✅ MATCHES (result)
field :agent_uuid, :string                    # ✅ MATCHES (agentUuid)
field :scheduled_at, :naive_datetime          # ✅ MATCHES (scheduledDate)
field :assigned_at, :naive_datetime           # ⚠️ COMPUTED (from stateTransitions)
field :completed_at, :naive_datetime          # ⚠️ COMPUTED (from stateTransitions)

belongs_to :stage_instance, StageInstance     # ✅ MATCHES (stageId)
belongs_to :job, Job                          # ⚠️ MISSING IN GOCD (we added this - good!)
```

### Missing Fields

- ❌ `ignored` - boolean flag
- ❌ `identifier` - JobIdentifier (full path)
- ❌ `run_on_all_agents` - from config
- ❌ `run_multiple_instance` - from config
- ❌ `original_job_id` - for reruns
- ❌ `rerun` - boolean
- ❌ `pipeline_still_configured` - validation flag

### Field Issues

- ⚠️ `assigned_at` / `completed_at` - GoCD gets these from stateTransitions, we're denormalizing
- ✅ `belongs_to :job` - we added this to link back to config, GoCD doesn't have it explicitly (resolves via name)

---

## Summary of Issues

### Critical Gaps

1. **Job artifacts** - completely missing (critical feature!)
2. **BuildCause** - oversimplified to trigger_by + trigger_message
3. **Stage rerun tracking** - no rerun_of_counter, latest_run fields
4. **Job rerun tracking** - no original_job_id, rerun, ignored fields
5. **Approval authorization** - Approval object has authorization (users/roles)
6. **Tabs configuration** - missing from Job
7. **Material polymorphism** - missing type-specific fields

### Type Mismatches

1. **Job.timeout** - should be `:string` not `:integer` (allows "never")
2. **Task.timeout** - should allow nil
3. **PipelineInstance status** - doesn't exist in GoCD (computed from stages)

### Design Questions

1. **Denormalization** - Should we copy config fields to instances (fetch_materials, clean_working_dir, etc.) like GoCD does?
2. **State tracking** - Should we store assigned_at/completed_at or compute from stateTransitions?
3. **Material types** - Separate schemas vs polymorphic with :map?
4. **BuildCause** - Full object vs simplified fields?

---

## Recommended Actions

### Immediate Fixes (Phase 2 continuation)

1. Fix `Job.timeout` type to `:string`
2. Add `run_on_all_agents` to Job
3. Add missing artifact configuration
4. Add basic rerun tracking fields

### Phase 3: Full Fidelity

1. Implement BuildCause properly
2. Add full Approval object support
3. Implement StateTransitions tracking
4. Add all missing instance tracking fields
5. Material type-specific schemas or enhanced polymorphism

