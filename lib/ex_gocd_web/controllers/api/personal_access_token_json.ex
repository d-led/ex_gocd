defmodule ExGoCDWeb.API.PersonalAccessTokenJSON do
  alias ExGoCD.Accounts.PersonalAccessToken

  def index(%{tokens: tokens}) do
    Enum.map(tokens, &token_json/1)
  end

  def show(%{token: token}) do
    token_json(token)
  end

  def create(%{token: token}) do
    token_json(token)
    |> Map.put(:token, token.token)
  end

  defp token_json(%PersonalAccessToken{} = token) do
    %{
      id: token.id,
      description: token.description,
      username: get_username(token),
      created_at: format_time(token.inserted_at),
      last_used_at: format_time(token.last_used_at),
      revoked: token.revoked,
      revoked_at: format_time(token.revoked_at),
      revoked_by: token.revoked_by,
      revoke_cause: token.revoke_cause
    }
  end

  defp get_username(token) do
    if Ecto.assoc_loaded?(token.user) && token.user do
      token.user.username
    end
  end

  defp format_time(nil), do: nil

  defp format_time(dt) do
    DateTime.to_iso8601(dt)
  end
end
