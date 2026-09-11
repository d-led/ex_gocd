defmodule ExGoCDWeb.API.MailserverConfigController do
  @moduledoc """
  Mail server (SMTP) configuration. GoCD parity: GET /go/api/config/mailserver.
  """
  use ExGoCDWeb, :controller

  alias ExGoCD.Crypto

  def show(conn, _params) do
    config = Application.get_env(:ex_gocd, ExGoCD.Mailer, [])

    json(conn, %{
      "hostname" => config[:relay] || "localhost",
      "port" => config[:port] || 25,
      "username" => config[:username] || "",
      "encrypted_password" => encrypted_password(config[:password]),
      "tls" => tls?(config),
      "sender_email" => sender_email(),
      "admin_email" => System.get_env("ADMIN_EMAIL") || sender_email()
    })
  end

  defp encrypted_password(nil), do: ""
  defp encrypted_password(""), do: ""
  defp encrypted_password(password), do: Crypto.encrypt(password)

  defp tls?(config) do
    config[:ssl] == true or config[:tls] == :always
  end

  defp sender_email do
    case Application.get_env(:ex_gocd, :mailer_from, {"ex_gocd", "noreply@exgocd.local"}) do
      {_name, email} -> email
      email when is_binary(email) -> email
      _ -> "noreply@exgocd.local"
    end
  end
end
