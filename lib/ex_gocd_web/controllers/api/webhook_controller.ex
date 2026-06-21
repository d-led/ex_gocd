defmodule ExGoCDWeb.API.WebhookController do
  use ExGoCDWeb, :controller
  require Logger

  alias ExGoCD.Materials.Poller

  action_fallback ExGoCDWeb.FallbackController

  @doc """
  POST /api/admin/materials/git/notify
  Triggers manual polling for git materials matching the provided repository_url.
  """
  def git_notify(conn, params) do
    confirm_header = get_req_header(conn, "confirm")

    if List.first(confirm_header) == "true" do
      case Map.get(params, "repository_url") do
        url when is_binary(url) and url != "" ->
          # Trigger update in the background asynchronously
          Task.start(fn ->
            Poller.poll_materials_by_url(url)
          end)

          conn
          |> put_status(:accepted)
          |> json(%{
            "message" => "The material is now scheduled for an update. Please check relevant pipeline(s) for status."
          })

        _ ->
          conn
          |> put_status(:bad_request)
          |> json(%{"error" => "Missing parameter 'repository_url'"})
      end
    else
      conn
      |> put_status(:bad_request)
      |> json(%{"error" => "Missing required header 'Confirm: true'"})
    end
  end

  @doc """
  POST /api/webhooks/github/notify
  GitHub push webhook.
  """
  def github_notify(conn, params) do
    if verify_github_signature(conn) do
      case extract_github_url(params) do
        url when is_binary(url) and url != "" ->
          Task.start(fn ->
            Poller.poll_materials_by_url(url)
          end)

          conn
          |> put_status(:accepted)
          |> text("Accepted")

        _ ->
          conn
          |> put_status(:bad_request)
          |> text("Missing repository URL in payload")
      end
    else
      conn
      |> put_status(:unauthorized)
      |> text("Invalid signature")
    end
  end

  @doc """
  POST /api/webhooks/gitlab/notify
  GitLab push webhook.
  """
  def gitlab_notify(conn, params) do
    if verify_gitlab_token(conn) do
      case extract_gitlab_url(params) do
        url when is_binary(url) and url != "" ->
          Task.start(fn ->
            Poller.poll_materials_by_url(url)
          end)

          conn
          |> put_status(:accepted)
          |> text("Accepted")

        _ ->
          conn
          |> put_status(:bad_request)
          |> text("Missing repository URL in payload")
      end
    else
      conn
      |> put_status(:unauthorized)
      |> text("Invalid token")
    end
  end

  # Helper functions

  defp verify_github_signature(conn) do
    case System.get_env("GOCD_WEBHOOK_SECRET") do
      nil ->
        true

      "" ->
        true

      secret ->
        case get_req_header(conn, "x-hub-signature-256") do
          [signature] ->
            if String.starts_with?(signature, "sha256=") do
              "sha256=" <> expected_sig = signature
              raw_body = conn.assigns[:raw_body] || ""
              actual_sig = :crypto.mac(:hmac, :sha256, secret, raw_body) |> Base.encode16(case: :lower)
              Plug.Crypto.secure_compare(actual_sig, expected_sig)
            else
              false
            end

          _ ->
            false
        end
    end
  end

  defp verify_gitlab_token(conn) do
    case System.get_env("GOCD_WEBHOOK_SECRET") do
      nil ->
        true

      "" ->
        true

      secret ->
        case get_req_header(conn, "x-gitlab-token") do
          [token] ->
            Plug.Crypto.secure_compare(token, secret)

          _ ->
            false
        end
    end
  end

  defp extract_github_url(params) do
    case params do
      %{"repository" => %{"clone_url" => url}} when is_binary(url) -> url
      %{"repository" => %{"ssh_url" => url}} when is_binary(url) -> url
      %{"repository" => %{"git_url" => url}} when is_binary(url) -> url
      _ -> nil
    end
  end

  defp extract_gitlab_url(params) do
    case params do
      %{"repository" => %{"git_http_url" => url}} when is_binary(url) -> url
      %{"repository" => %{"git_ssh_url" => url}} when is_binary(url) -> url
      %{"repository" => %{"url" => url}} when is_binary(url) -> url
      %{"project" => %{"git_http_url" => url}} when is_binary(url) -> url
      %{"project" => %{"git_ssh_url" => url}} when is_binary(url) -> url
      _ -> nil
    end
  end
end
