defmodule ExGoCDWeb.ConfirmHeader do
  @moduledoc """
  A mutating API request that carries no body has to say, with `X-GoCD-Confirm`,
  that the empty request was meant (GoCD's `ApiController#verifyContentType`).
  Tests say so with `confirmed/1` and check the refusal with
  `assert_unconfirmed_request_refused/1`, so neither the header name nor GoCD's
  wording is repeated in every file.
  """
  import ExUnit.Assertions
  import Phoenix.ConnTest
  import Plug.Conn

  @refusal %{"message" => "Missing required header 'X-GoCD-Confirm' with value 'true'"}

  @doc "Marks the empty request this connection is about to send as intended."
  def confirmed(conn), do: put_req_header(conn, "x-gocd-confirm", "true")

  @doc "Asserts the API refused an empty request that carried no confirmation."
  def assert_unconfirmed_request_refused(conn) do
    assert json_response(conn, 400) == @refusal
  end
end
