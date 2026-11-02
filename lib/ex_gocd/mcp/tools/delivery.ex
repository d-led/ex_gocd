defmodule ExGoCD.Mcp.Tools.Delivery do
  @moduledoc """
  A review of the flow a delivery pipeline has, and of nothing else.

  `gocd_audit_config` asks whether anything can run the jobs, and
  `gocd_validate_pipeline` asks whether the graph holds together. This family asks
  the third flow question: given what is configured and which agents exist, does
  the *shape* hold?

    * **what passes between pipelines** — a deploy that depends on a build and
      also checks out the same repository can rebuild what was built, so what it
      ships is not the artifact that was tested; a pipeline others depend on that
      publishes nothing leaves them nothing to take; a `fetch` from a pipeline
      that is not a dependency takes whatever was produced last;
    * **the shape the fleet can run** — a stage of jobs that only one agent can
      take is a queue however it is drawn, and a fleet of one agent makes every
      parallel stage serial;
    * **where it runs** — a deploy in no environment is taken by the default pool.

  What a job does is the author's business and is deliberately not reviewed: the
  commands, the number of stages, whether a stage is gated, and whether the
  configuration lives in a repository are decisions the server cannot judge from
  the outside. It says what it can assert about the edges, and stops there.
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
        "Reviews the flow of a pipeline, or of a whole graph, and nothing else: what " <>
          "depends on what, what is passed along those edges, and whether the fleet can " <>
          "run the shape. Names a deploy that depends on a build and also checks out the " <>
          "same repository (it can rebuild what was built, so it ships something nobody " <>
          "tested), a pipeline others depend on that publishes no artifacts, a fetch from " <>
          "a pipeline it does not depend on, a stage of jobs that only as many agents as " <>
          "the fleet has can take at once, and a deploy in no environment. What a job " <>
          "does — its commands, its stages, its gates, where its config is kept — is the " <>
          "author's decision and is not reviewed. Writes nothing. With no arguments it " <>
          "reviews the configuration as it stands.",
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
    "Nothing to report: every edge holds. What depends on what, what is passed " <>
      "along it, and whether the fleet can run the shape are all consistent."
  end

  defp review_text([], definitions) do
    "#{length(definitions)} pipeline(s) reviewed; no findings. Their dependencies and " <>
      "the artifacts they pass along hold together."
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
