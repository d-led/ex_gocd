defmodule ExGoCD.Mcp.Completions do
  @moduledoc """
  The values a client offers while a person is typing an argument.

  Only two kinds of reference can be completed, because only they name something
  the server owns: a prompt's argument, and the variable of a resource template.
  Both of the interesting completions here are the pipeline names this server
  has — the same names `gocd_list_pipelines` lists — filtered by what has been
  typed so far.

  A completion is a convenience, not a permission: whatever a client settles on
  is checked again by the tool or the resource it is used with. So a name that
  appears in this list is a name that exists, not a name the caller may use.
  """

  alias ExGoCD.Pipelines

  # A menu is a menu: more than this and the client is reading rather than
  # choosing. `hasMore` says the rest is there.
  @max_values 100

  @doc """
  Completions for one reference's argument.

  `ref` is `%{"type" => "ref/prompt", "name" => "diagnose_pipeline"}` or
  `%{"type" => "ref/resource", "uri" => "gocd://pipelines/{name}"}`; `argument`
  is `%{"name" => "pipeline", "value" => "bu"}`. A reference this server knows
  nothing about completes to nothing rather than to an error — the specification
  treats an empty completion as a normal answer.
  """
  @spec complete(map(), map(), map()) :: %{String.t() => term()}
  def complete(ref, argument, _ctx) do
    case candidates(ref, argument) do
      nil -> %{"values" => [], "total" => 0, "hasMore" => false}
      values -> matching(values, argument["value"])
    end
  end

  defp candidates(%{"type" => "ref/prompt", "name" => name}, %{"name" => "pipeline"})
       when name in ["diagnose_pipeline", "what_changed"],
       do: pipeline_names()

  defp candidates(%{"type" => "ref/prompt", "name" => "fleet_health"}, %{"name" => "days"}),
    do: ["7", "14", "30", "90"]

  defp candidates(
         %{"type" => "ref/resource", "uri" => "gocd://pipelines/{name}"},
         %{"name" => "name"}
       ),
       do: pipeline_names()

  defp candidates(_ref, _argument), do: nil

  defp pipeline_names, do: Pipelines.list_pipelines() |> Enum.map(& &1.name) |> Enum.sort()

  defp matching(values, prefix) do
    prefix = prefix |> to_string() |> String.downcase()

    matches = Enum.filter(values, &String.starts_with?(String.downcase(&1), prefix))
    shown = Enum.take(matches, @max_values)

    %{"values" => shown, "total" => length(matches), "hasMore" => length(matches) > length(shown)}
  end
end
