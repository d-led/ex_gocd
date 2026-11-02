defmodule ExGoCD.Mcp.CompletionsTest do
  @moduledoc """
  The menu a client offers while a person types an argument: the names that
  exist, filtered by what has been typed, and nothing when the server has
  nothing to suggest.
  """

  use ExGoCD.DataCase, async: true

  import ExGoCD.PipelinesFixtures

  alias ExGoCD.Mcp.Completions

  @ctx %{user: nil, base_url: "http://localhost:4000", remote_ip: "127.0.0.1"}

  setup do
    insert_pipeline("build-app")
    insert_pipeline("build-docs")
    insert_pipeline("deploy")
    :ok
  end

  test "a prompt's pipeline argument completes from the pipelines that exist" do
    ref = %{"type" => "ref/prompt", "name" => "diagnose_pipeline"}

    assert Completions.complete(ref, %{"name" => "pipeline", "value" => "buil"}, @ctx) == %{
             "values" => ["build-app", "build-docs"],
             "total" => 2,
             "hasMore" => false
           }
  end

  test "an empty prefix offers everything, in order" do
    ref = %{"type" => "ref/prompt", "name" => "what_changed"}

    assert %{"values" => ["build-app", "build-docs", "deploy"], "total" => 3} =
             Completions.complete(ref, %{"name" => "pipeline", "value" => ""}, @ctx)
  end

  test "the resource template completes the same names" do
    ref = %{"type" => "ref/resource", "uri" => "gocd://pipelines/{name}"}

    assert %{"values" => ["deploy"], "total" => 1} =
             Completions.complete(ref, %{"name" => "name", "value" => "dep"}, @ctx)
  end

  test "the period argument offers periods rather than free text" do
    ref = %{"type" => "ref/prompt", "name" => "fleet_health"}

    assert %{"values" => ["7", "14", "30", "90"], "total" => 4} =
             Completions.complete(ref, %{"name" => "days", "value" => ""}, @ctx)
  end

  test "a reference the server does not know is an empty menu, not an error" do
    assert %{"values" => [], "total" => 0, "hasMore" => false} =
             Completions.complete(
               %{"type" => "ref/prompt", "name" => "nonexistent"},
               %{"name" => "pipeline", "value" => ""},
               @ctx
             )
  end
end
