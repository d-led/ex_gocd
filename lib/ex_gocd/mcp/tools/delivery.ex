defmodule ExGoCD.Mcp.Tools.Delivery do
  @moduledoc """
  A design review against the principles a deployment pipeline exists to serve.

  `gocd_audit_config` asks whether anything can run the jobs, and
  `gocd_validate_pipeline` asks whether the graph holds together. Neither asks
  whether the pipeline is *any good*, which is a different question and the one
  Farley's *Continuous Delivery* — written alongside the Cruise team that became
  GoCD — answers with five properties:

    * **build once** — the artifact is built once and promoted, so what reaches
      production is what was tested;
    * **fast feedback** — the first stage answers "does this work?" without a
      person in front of it;
    * **parallel feedback** — a stage's jobs run at the same time, so the answer
      is minutes and not a queue;
    * **as code** — the topology is reviewed with the code it builds;
    * **clean environment** — a stage does not start on the last run's files.

  It is a static review: it can say the pipeline is arranged so a bad build would
  be noticed, never that a build is good. The findings are the anti-patterns
  worth naming — a deploy that rebuilds, a gate where feedback should be, a
  stage serialised by construction, and a pipeline that exists nowhere but in one
  database.
  """

  alias ExGoCD.{ConfigAudit, DeliveryReview, Pipelines}
  alias ExGoCD.Mcp.{Render, Tool}
  alias ExGoCD.Mcp.Tools.PipelineConfig

  @names ~w(gocd_review_delivery)

  @tools [
    %{
      "name" => "gocd_review_delivery",
      "title" => "Review a pipeline against the delivery principles",
      "description" =>
        "Reviews a pipeline, or a whole graph, against the properties a deployment " <>
          "pipeline is supposed to have: build once (a deploy that rebuilds is not " <>
          "deploying what was tested), fast feedback (a gate on the first stage means " <>
          "feedback waits for a person), parallel feedback (tasks run one after another, " <>
          "jobs do not — and a stage of jobs that only one agent can take is a queue " <>
          "however it is drawn), explicit stages and jobs (a shell one-liner is a script " <>
          "with a pipeline drawn around it), releasable by the pipeline itself (one that " <>
          "ends at a gate leaves the real decision outside it; a deploy in no environment " <>
          "runs on the default pool), as code, and a clean environment. For what is " <>
          "configured it also reads the last runs: a pipeline that failed twice in a row " <>
          "is a red pipeline, which comes before everything else. Writes nothing. With " <>
          "no arguments it reviews the configuration as it stands.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "definition" => PipelineConfig.definition_schema(),
          "pipelines" => %{
            "type" => "array",
            "description" => "A graph to review: several pipelines in one call.",
            "items" => PipelineConfig.definition_schema()
          }
        }
      },
      "annotations" => Tool.read_only()
    }
  ]

  @doc "The definitions of this family's tools."
  @spec definitions() :: [map()]
  def definitions, do: @tools

  @doc "The names of this family's tools."
  @spec names() :: [String.t()]
  def names, do: @names

  @doc "Whether this family answers to a tool name."
  @spec handles?(String.t()) :: boolean()
  def handles?(name), do: name in @names

  @doc "Calls one of this family's tools."
  @spec call(String.t(), map(), Tool.ctx()) :: Tool.result() | :unknown_tool
  def call("gocd_review_delivery", args, ctx), do: review(args, ctx)
  def call(_name, _args, _ctx), do: :unknown_tool

  defp review(args, _ctx) do
    with {:ok, definitions} <- definitions(args) do
      context = %{agents: ConfigAudit.fleet(), environments: ConfigAudit.environments()}
      findings = reviewed(definitions, Pipelines.list_pipelines(), context)
      Tool.ok(review_text(findings, definitions), review_answer(findings))
    end
  end

  # No arguments means "the configuration as it stands"; anything else is a
  # proposal, and then only the proposal's findings are the answer.
  defp definitions(args) do
    if args["definition"] == nil and args["pipelines"] == nil do
      {:ok, []}
    else
      PipelineConfig.preview_graph(args)
    end
  end

  defp reviewed([], configured, context), do: DeliveryReview.review([], configured, context)

  defp reviewed(definitions, configured, context) do
    reviewed = definitions |> Enum.map(& &1.name) |> MapSet.new()

    definitions
    |> DeliveryReview.review(configured, context)
    |> Enum.filter(&MapSet.member?(reviewed, &1.subject))
  end

  defp review_text([], []) do
    "Nothing to report: the configuration follows the principles that can be " <>
      "checked statically. Build once, fast feedback, parallel feedback, as code " <>
      "and clean environments are all satisfied."
  end

  defp review_text([], definitions) do
    "#{length(definitions)} pipeline(s) reviewed; no findings. They build once, give " <>
      "feedback early and in parallel, and start clean."
  end

  defp review_text(findings, _definitions) do
    findings
    |> Enum.group_by(& &1.principle)
    |> Enum.sort_by(fn {principle, _findings} -> principle end)
    |> Enum.map(fn {principle, group} ->
      "#{DeliveryReview.principles()[principle]} (#{length(group)}):\n" <>
        Render.bullets(Enum.map(group, & &1.message))
    end)
    |> Enum.join("\n\n")
    |> then(&(summary(findings) <> "\n\n" <> &1))
  end

  defp summary(findings) do
    counts =
      findings
      |> Enum.frequencies_by(& &1.principle)
      |> Enum.sort_by(fn {principle, _count} -> principle end)
      |> Enum.map_join(", ", fn {principle, count} ->
        "#{count} #{DeliveryReview.principles()[principle] |> String.downcase()}"
      end)

    "#{length(findings)} finding(s): #{counts}."
  end

  defp review_answer(findings) do
    %{
      "findings" =>
        Enum.map(findings, fn finding ->
          %{
            "principle" => to_string(finding.principle),
            "code" => to_string(finding.code),
            "subject" => finding.subject,
            "message" => finding.message
          }
        end)
    }
  end
end
