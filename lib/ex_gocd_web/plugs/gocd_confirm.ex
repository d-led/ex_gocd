defmodule ExGoCDWeb.Plugs.GoCDConfirm do
  @moduledoc """
  GoCD's rule for a mutating API request, ported from `ApiController#verifyContentType`:
  a POST/PUT/PATCH that carries a body must be JSON, and one that carries no body
  must say, with the `X-GoCD-Confirm` header, that the empty request was meant.

  Only the presence of the header matters, as in GoCD — its value is not read.
  That is why the documented curl for cancelling a stage sends the header while
  the one for running selected jobs, which posts a body, does not.

  GoCD wires this per controller (`before("/*", mimeType, this::verifyContentType)`),
  not per pipeline: the plugin, environment, permission and site-URL controllers
  never ask. A controller here opts in for the same reason its GoCD counterpart
  does, so the two disagree only where one of them changed its mind.
  """
  import Plug.Conn

  @mutating ~w(POST PUT PATCH)

  def init(opts), do: opts

  def call(conn, _opts) do
    if unconfirmed_empty_request?(conn) do
      conn
      |> put_status(:bad_request)
      |> Phoenix.Controller.json(%{
        message: "Missing required header 'X-GoCD-Confirm' with value 'true'"
      })
      |> halt()
    else
      conn
    end
  end

  defp unconfirmed_empty_request?(conn) do
    conn.method in @mutating and not carried_anything?(conn) and not confirmed?(conn)
  end

  # A request that carried nothing is the one GoCD asks to confirm. The length
  # header is what a real connection reports; `body_params` covers the test
  # adapter, which hands the body over without setting one.
  defp carried_anything?(conn) do
    content_length(conn) > 0 or parsed_params(conn) != %{}
  end

  defp content_length(conn) do
    case get_req_header(conn, "content-length") do
      [length] ->
        case Integer.parse(length) do
          {bytes, ""} -> bytes
          _ -> 0
        end

      [] ->
        if Enum.any?(
             get_req_header(conn, "transfer-encoding"),
             &(String.downcase(&1) == "chunked")
           ),
           do: 1,
           else: 0
    end
  end

  # A struct is what an unread body looks like (`Plug.Conn.Unfetched`), so only a
  # plain map counts as parameters that were actually parsed.
  defp parsed_params(%{body_params: params}) when is_map(params) and not is_struct(params),
    do: params

  defp parsed_params(_conn), do: %{}

  defp confirmed?(conn), do: get_req_header(conn, "x-gocd-confirm") != []
end
