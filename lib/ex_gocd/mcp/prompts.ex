defmodule ExGoCD.Mcp.Prompts do
  @moduledoc """
  The workflows a person asks for most often, written down once: which calls to
  make, in which order, and what to conclude from them.

  A prompt is not a tool. A tool answers a question; a prompt tells an assistant
  how to go about answering a *better* question — the order matters when the
  second call depends on the first ("which job failed" before "read its
  console"), and a model that invents the order spends turns rediscovering it.
  Each prompt says what to do when a call comes back empty, too, because that is
  where an assistant most often guesses.
  """

  @prompts [
    %{
      "name" => "diagnose_pipeline",
      "title" => "Why did this pipeline fail?",
      "description" =>
        "Walk a failed run down from its status to the console of the job that broke, and " <>
          "say what to do next. Uses the pipeline, instance, job and console tools in the " <>
          "one order that does not read the wrong job.",
      "arguments" => [
        %{
          "name" => "pipeline",
          "description" => "The pipeline's name.",
          "required" => true
        }
      ]
    },
    %{
      "name" => "why_is_nothing_running",
      "title" => "Why is nothing running?",
      "description" =>
        "Separate the three reasons work does not move — nothing queued, nothing that can " <>
          "take it, or the server refusing to schedule — and say which it is.",
      "arguments" => []
    },
    %{
      "name" => "what_changed",
      "title" => "What changed between two runs?",
      "description" =>
        "Compare two runs of a pipeline: the material revisions, the environment, and " <>
          "whether the configuration itself changed — then say what is most likely " <>
          "responsible for a difference in outcome.",
      "arguments" => [
        %{"name" => "pipeline", "description" => "The pipeline's name.", "required" => true},
        %{
          "name" => "from",
          "description" => "The earlier run's counter; omit for \"the run before\".",
          "required" => false
        },
        %{
          "name" => "to",
          "description" => "The later run's counter; omit for the latest.",
          "required" => false
        }
      ]
    },
    %{
      "name" => "fleet_health",
      "title" => "How has this server been doing?",
      "description" =>
        "A period's worth of the server's own numbers — pass rates, wait times, agent " <>
          "utilization — with the failures worth naming, rather than a list of everything.",
      "arguments" => [
        %{
          "name" => "days",
          "description" => "How far back to look, in days. Default 7.",
          "required" => false
        }
      ]
    }
  ]

  @doc "The prompts a client can list."
  @spec definitions() :: [map()]
  def definitions, do: @prompts

  @doc """
  One prompt, filled in.

  Answers `{:ok, %{"description" => text, "messages" => [...]}}` — the shape
  `prompts/get` returns — or an error sentence naming the argument that is
  missing.
  """
  @spec get(String.t(), map(), map()) :: {:ok, map()} | {:error, String.t()}
  def get("diagnose_pipeline", args, _ctx) do
    with {:ok, pipeline} <- required(args, "pipeline") do
      prompt(
        "Diagnosing a failed run of #{pipeline}",
        """
        Diagnose the most recent run of the pipeline `#{pipeline}`.

        1. `gocd_pipeline_status` with that name — if the latest run passed, say so and stop;
           a "failure" that is not there is the answer.
        2. `gocd_pipeline_instance` with the counter the status reported, so you know which
           stage and which job ended it. A manual stage still `Awaiting` is not a failure —
           it is waiting for a person, and say that instead.
        3. `gocd_job` for the job that failed, to get its build id and the agent that ran it.
        4. `gocd_job_console` with `lines: 200` — read the *end* of the log. Name the failing
           command and its error verbatim; do not paraphrase a stack trace.
        5. `gocd_pipeline_analytics` for that pipeline, 30 days — is this the first time, or
           the latest of several? A run that fails only sometimes is a different problem.

        Report: what failed, the error in one line, whether it is new or recurring, and the
        single next action (fix the code, re-run the failed jobs, or ask about the agent if
        the console shows the agent itself broke). Quote the run counter and the job name so
        the reader can open the same page.
        """
      )
    end
  end

  def get("why_is_nothing_running", args, _ctx) do
    if Map.keys(args) -- ["days"] == [] do
      prompt(
        "Why is no work moving?",
        """
        Find out why this server is not making progress.

        1. `gocd_server_info` — is it in maintenance mode? Is disk space critical? Either
           answers the question on its own; say so and stop.
        2. `gocd_queue` — how many jobs are pending, and are any of them in the in-memory
           queue rather than the database? Take one pending job's `resources` and call
           `gocd_queue` again with them: the diagnosis names the agents that could run it and
           what the others are missing.
        3. `gocd_list_agents` — how many agents are idle and *enabled*? Agents in LostContact
           or disabled agents are the answer when the queue is not empty and nothing moves.
        4. `gocd_dashboard` filtered by the affected pipeline's group — is the pipeline paused
           or locked? A locked pipeline is not a broken agent.

        Report which of the three it is — nothing queued, nothing that can take it, or the
        server refusing to schedule — with the numbers that show it, and the one action that
        would unblock it. Do not restart or cancel anything to find out.
        """
      )
    else
      {:error, "`why_is_nothing_running` takes no arguments."}
    end
  end

  def get("what_changed", args, _ctx) do
    with {:ok, pipeline} <- required(args, "pipeline"),
         {:ok, to} <- counter(args, "to"),
         {:ok, from} <- counter(args, "from") do
      prompt(
        "What changed around run #{to || "the latest"} of #{pipeline}",
        """
        Explain what changed between two runs of `#{pipeline}`.

        1. `gocd_pipeline_history` for the pipeline, if you do not already know the counters:
           take `#{to || "the latest"}` and the run before it (`#{from || "the counter before it"}`).
        2. `gocd_compare_pipeline_instances` with those two counters — each material's revision
           in both, the modifications in between, the environment variables, and whether the
           configuration changed at all.
        3. `gocd_pipeline_config_diff` for the later run — the configuration difference itself,
           when the comparison says there was one. "No configuration change" is a real answer;
           it moves suspicion to the code.
        4. `gocd_audit_log` with `resource_name` set to the pipeline and a date range covering
           the two runs — who paused it, triggered it, or changed anything near them.

        Report the changes in the order they could explain a difference: material revisions
        first, then configuration, then human actions. If none of them changed, say that
        plainly — then the difference is inside the code or the agent, and say which tool would
        look there next.
        """
      )
    end
  end

  def get("fleet_health", args, _ctx) do
    with {:ok, days} <- days(args) do
      prompt(
        "How this GoCD server has been doing over the last #{days} day(s)",
        """
        Summarise the last #{days} day(s) of this server, from its own numbers.

        1. `gocd_pipeline_analytics` with `days: #{days}` — the per-pipeline run counts and
           latest statuses, and the pipelines with the longest average wait. Name the three
           slowest to start; a queue nobody notices is the usual hidden cost.
        2. `gocd_pipeline_analytics` for any pipeline that is failing or slow, with the same
           window — its pass rate, mean time to recovery, and average build time. Use the
           comparison (this pipeline against the others) rather than an absolute threshold.
        3. `gocd_agent_analytics` with `days: #{days}` — job counts and successes per agent,
           with hostnames. An agent with many jobs and many failures is a machine to look at,
           not a pipeline to fix.
        4. `gocd_list_agents` — how many are idle and enabled right now, so the report separates
           "we are short of capacity" from "capacity is idle while work waits".

        Report five lines at most: what is healthy, what is failing, where the waiting is, what
        it costs, and the one thing to fix first. Give numbers with the claims, and say which
        tool each number came from when it is not obvious.
        """
      )
    end
  end

  def get(name, _args, _ctx) do
    {:error, "No prompt named `#{name}`. `prompts/list` says what there is."}
  end

  # ── arguments ──────────────────────────────────────────────────────

  defp required(args, key) do
    case args[key] do
      value when is_binary(value) and value != "" -> {:ok, String.trim(value)}
      _missing -> {:error, "`#{key}` is required."}
    end
  end

  defp counter(args, key) do
    case args[key] do
      nil -> {:ok, nil}
      value when is_integer(value) -> {:ok, value}
      value when is_binary(value) -> parse_counter(value, key)
      _other -> {:error, "`#{key}` must be an integer."}
    end
  end

  defp parse_counter(value, key) do
    case Integer.parse(String.trim(value)) do
      {number, ""} -> {:ok, number}
      _not_a_number -> {:error, "`#{key}` must be an integer."}
    end
  end

  defp days(args) do
    case args["days"] do
      nil -> {:ok, 7}
      value when is_integer(value) and value > 0 -> {:ok, min(value, 365)}
      value when is_binary(value) -> parse_days(value)
      _other -> {:error, "`days` must be a positive integer."}
    end
  end

  defp parse_days(value) do
    case Integer.parse(String.trim(value)) do
      {number, ""} when number > 0 -> {:ok, min(number, 365)}
      _not_a_number -> {:error, "`days` must be a positive integer."}
    end
  end

  defp prompt(description, text) do
    {:ok,
     %{
       "description" => description,
       "messages" => [
         %{"role" => "user", "content" => %{"type" => "text", "text" => String.trim(text)}}
       ]
     }}
  end
end
