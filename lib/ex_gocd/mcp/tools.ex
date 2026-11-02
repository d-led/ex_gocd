defmodule ExGoCD.Mcp.Tools do
  @moduledoc """
  The tools the MCP server offers, grouped the way a reader asks for them, and
  the one place a tool name becomes a module.

  Each family is a module under this one — `Tools.Pipelines`, `Tools.Agents`, and
  so on — that owns its definitions, answers `handles?/1`, and dispatches with
  `call/3`. A family is a group of questions a person actually asks together, so
  the grouping is the documentation: `families/0` is what a page renders and
  `definitions/0` is what the protocol serves, and they cannot disagree because
  the second is derived from the first.

  Annotations are honest about what each tool does: the ones that only read say
  so, the ones that change something say that too, and the ones that can throw
  work away say `destructiveHint`.
  """

  alias ExGoCD.Mcp.Tool

  alias ExGoCD.Mcp.Tools.{
    Administration,
    Agents,
    Analytics,
    Config,
    Jobs,
    PipelineConfig,
    PipelineOperations,
    Pipelines,
    Server,
    Stages
  }

  # How a reader asks for them, which is not how the protocol needs them ordered.
  @families [
    {"The server", [Server]},
    {"Pipelines", [Pipelines]},
    {"Acting on pipelines", [PipelineOperations]},
    {"Authoring pipelines", [PipelineConfig]},
    {"Stages", [Stages]},
    {"Jobs", [Jobs]},
    {"Agents", [Agents]},
    {"Analytics", [Analytics]},
    {"Configuration", [Config]},
    {"Administration", [Administration]}
  ]

  @modules Enum.flat_map(@families, fn {_label, modules} -> modules end)

  @doc """
  The tools, grouped the way a reader asks for them, as their own definitions.

  Each entry is `{label, [definition]}`, and a definition is the map the protocol
  serves — name, title, description, `inputSchema` and annotations — so a page
  that renders this shows what a client is actually offered, not a retelling.
  """
  @spec families() :: [{String.t(), [map()]}]
  def families do
    for {label, modules} <- @families,
        do: {label, Enum.flat_map(modules, & &1.definitions())}
  end

  @doc "The `tools/list` result."
  @spec definitions() :: [map()]
  def definitions, do: Enum.flat_map(@modules, & &1.definitions())

  @doc "The tool names, sorted."
  @spec names() :: [String.t()]
  def names, do: definitions() |> Enum.map(& &1["name"]) |> Enum.sort()

  @doc "How many tools there are, for the pages that say so."
  @spec count() :: non_neg_integer()
  def count, do: length(definitions())

  @doc "The tools that change something, so a page need not claim it by hand."
  @spec writers() :: [map()]
  def writers, do: Enum.reject(definitions(), &(&1["annotations"]["readOnlyHint"] == true))

  @doc "Whether any family answers to this tool name."
  @spec handles?(String.t()) :: boolean()
  def handles?(name), do: Enum.any?(@modules, & &1.handles?(name))

  @doc """
  Calls a tool.

  `ctx` carries what a tool cannot work out for itself and must not guess: who
  the request authenticated as (so the same permission rules apply as on the API
  and the pages), where this server answers (so a link opens), and the caller's
  address (which the audit log records).
  """
  @spec call(String.t(), map(), Tool.ctx()) :: Tool.result() | :unknown_tool
  def call(name, arguments, ctx) when is_map(arguments) do
    case Enum.find(@modules, & &1.handles?(name)) do
      nil -> :unknown_tool
      module -> module.call(name, arguments, ctx)
    end
  end

  def call(_name, _arguments, _ctx), do: {:error, "Tool arguments must be a JSON object."}
end
