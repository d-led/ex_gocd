# GoCD Missing Database Schemas Analysis

This document provides a detailed analysis of the database schemas present in original GoCD (Java/Hibernate/PostgreSQL) that are currently missing or simplified in our Phoenix Elixir rewrite (`ex_gocd`). It outlines what needs to be implemented to achieve full feature parity, particularly regarding the **Value Stream Map (VSM)**, **stage/job logs storage**, and **artifact management**.

---

## 1. Console Log Storage & Metadata Schema

### Original GoCD Architecture
In GoCD, console logs are streamed from agents to the server. The server stores them as flat files under the artifact directory:
`artifacts/pipelines/[pipeline_name]/[pipeline_counter]/[stage_name]/[stage_counter]/[job_name]/cruise-output/console.log`

However, GoCD maintains structured metadata to serve and query these logs:
1. **Console Line Offsets / Indexes**: To support pagination, tailing, and console search, the server parses or tracks the seek offset.
2. **Job Console Cache / State**: GoCD keeps memory/cache mappings of active console file descriptors and pointers to handle high-concurrency writes from agents.

### Current Gap in Phoenix Rewrite
- We do not store log metadata in the database.
- We do not have a dedicated `ConsoleLog` schema to manage log offsets, line counts, or storage paths (e.g. local disk vs. S3/object storage).
- The Phoenix live view directly streams files, which is prone to memory/FD leaks under high load.

### Recommended Schema: `JobConsoleLog`
To store and retrieve console logs cleanly:
```elixir
schema "job_console_logs" do
  belongs_to :job_instance, ExGoCD.Pipelines.JobInstance
  field :file_path, :string         # Path to the raw console.log file
  field :file_size, :integer        # Current file size in bytes
  field :line_count, :integer       # Total number of lines written
  field :is_complete, :boolean      # True if job has finished and log is closed
  timestamps()
end
```

---

## 2. Pipeline Material Revisions (PMR) Schema

### Original GoCD Architecture: `pipelinematerialrevisions`
This is a critical junction table in GoCD. It connects a specific **Pipeline Instance** (run) to the exact **Material Revision** (commit/revision) that triggered it.

- **For SCM Materials**: Links to the specific `Modification` (e.g., commit SHA `05172d07...` of repository X).
- **For Pipeline Materials**: Links to the specific parent `PipelineInstance` run counter (e.g., pipeline A run #5).

### Current Gap in Phoenix Rewrite
- We do not have a `PipelineMaterialRevision` join table.
- A pipeline run does not know exactly which commit triggered it, except through faked mock data or simplistic latest-modification queries.
- **This is the root cause of the faked VSM page.** Without PMR records, the server cannot dynamically construct the exact graph of pipeline runs and material changes that led to a specific build.

### Required Database Tables
To solve this, we must implement:
1. `modifications` - Stores the SCM commits/revisions fetched from materials.
2. `pipeline_material_revisions` - Maps pipeline runs to their triggering material revisions.

#### SCM Modifications Schema: `modifications`
```elixir
schema "modifications" do
  belongs_to :material, ExGoCD.Pipelines.Material
  field :revision, :string          # Commit SHA, SVN revision, etc.
  field :committer_name, :string
  field :committer_email, :string
  field :comment, :string
  field :modified_time, :utc_datetime
  timestamps()
end
```

#### Junction Schema: `pipeline_material_revisions`
```elixir
schema "pipeline_material_revisions" do
  belongs_to :pipeline_instance, ExGoCD.Pipelines.PipelineInstance
  belongs_to :material, ExGoCD.Pipelines.Material
  belongs_to :modification, ExGoCD.Pipelines.Modification, optional: true
  field :parent_pipeline_instance_id, :integer, optional: true # Reference to upstream pipeline run
  timestamps()
end
```

---

## 3. Value Stream Map (VSM) Schema

### Original GoCD Architecture
The Value Stream Map is a Directed Acyclic Graph (DAG) computed dynamically for any pipeline instance. It uses the `pipeline_material_revisions` table to trace dependencies recursively:
- **Upstream**: Look up parent pipeline instances linked in PMR.
- **Downstream**: Query other PMR records where the current pipeline instance is listed as `parent_pipeline_instance_id`.

### Current Gap in Phoenix Rewrite
- The VSM is computed from static/hardcoded mock data in Elixir because the database lacks PMR linkages.
- To make VSM functional with real runs, the VSM generator must fetch the recursive relationships from the database tables defined above.

---

## 4. Artifact Metadata & Published Properties

### Original GoCD Architecture
GoCD supports two types of artifacts:
1. **Build Artifacts**: Tarballs, ZIPs, or binaries generated during a job.
2. **Test Artifacts**: JUnit XML reports parsed by the server to display test results.

Additionally, GoCD stores properties (`ArtifactPropertiesConfig`) extracted from build files (like test pass/fail counts, code coverage numbers) in the database to display trends and graphs.

### Current Gap in Phoenix Rewrite
- We lack an `Artifact` schema or metadata table to record what artifacts have been uploaded for a job.
- We have no metadata index tracking file hashes or properties.

### Recommended Schema: `JobArtifact`
```elixir
schema "job_artifacts" do
  belongs_to :job_instance, ExGoCD.Pipelines.JobInstance
  field :name, :string              # Artifact identifier
  field :type, :string              # "build" or "test"
  field :source_path, :string       # File path relative to job directory
  field :checksum, :string          # MD5/SHA checksum
  timestamps()
end
```

---

## 5. Security and Role-Based Access Control (RBAC)

### Original GoCD Architecture
GoCD features granular permissions:
1. **User Accounts & Roles**: Groups of users associated with specific LDAP, file, or OAuth plugins.
2. **Pipeline Group Permissions**: Defines view, operate, and admin permissions per pipeline group.
3. **Environment Permissions**: Controls who can deploy to environments (e.g., only release-managers can deploy to Production).

### Current Gap in Phoenix Rewrite
- Only a simple `User` model exists.
- There is no pipeline-level permission checking or role authorization schema.

---

## 6. Environment Definitions Config

### Original GoCD Architecture
An **Environment** (`EnvironmentConfig`) groups:
1. **Pipelines**: Only pipelines assigned to an environment can share agents of that environment.
2. **Agents**: Bound to the environment, preventing they run jobs from other environments (crucial for staging/production separation).
3. **Environment Variables**: Overrides variables for all pipelines inside it.

### Current Gap in Phoenix Rewrite
- We do not have a database schema to represent environments and their associations.

---

## Summary of Database Schema Action Plan

To support full feature parity without mocking:
1. **Phase 1 (Logs & VSM)**:
   - Create `modifications` and `pipeline_material_revisions` schemas.
   - Refactor `ValueStreamMap` module to traverse the database relationships dynamically.
   - Add a `job_console_logs` table to clean up log writes.
2. **Phase 2 (Artifacts & Properties)**:
   - Add `job_artifacts` schema.
3. **Phase 3 (Environments & RBAC)**:
   - Add `environments` and environment-agent mapping schemas.
