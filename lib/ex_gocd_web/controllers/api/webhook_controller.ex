defmodule ExGoCDWeb.API.WebhookController do
  use ExGoCDWeb, :controller
  require Logger

  alias ExGoCD.Materials.Poller

  action_fallback ExGoCDWeb.FallbackController

  # In test mode we poll synchronously so tests are deterministic and isolated.
  # In production, fire-and-forget via Task to avoid blocking the HTTP response.
  defp trigger_poll(url) do
    if Application.get_env(:ex_gocd, :sync_webhook_poll, false) do
      Poller.poll_materials_by_url(url)
    else
      Task.start(fn -> Poller.poll_materials_by_url(url) end)
    end
  end

  @doc """
  POST /api/admin/materials/git/notify
  Triggers manual polling for git materials matching the provided repository_url.
  """
  def git_notify(conn, params), do: admin_notify(conn, params)

  @doc """
  POST /api/webhooks/github/notify
  GitHub push webhook.
  """
  def github_notify(conn, params) do
    if verify_github_signature(conn) do
      case extract_github_url(params) do
        url when is_binary(url) and url != "" ->
          trigger_poll(url)

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
          trigger_poll(url)

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

  @doc """
  POST /api/webhooks/bitbucket-server/notify
  Bitbucket Server push webhook. Extracts repository URL from payload.
  Requires webhook secret verification when GOCD_WEBHOOK_SECRET is set.
  """
  def bitbucket_server_notify(conn, params) do
    if verify_webhook_secret(conn) do
      case extract_bitbucket_server_url(params) do
        url when is_binary(url) and url != "" ->
          trigger_poll(url)
          conn |> put_status(:accepted) |> text("Accepted")

        _ ->
          conn |> put_status(:bad_request) |> text("Missing repository URL in payload")
      end
    else
      conn
      |> put_status(:unauthorized)
      |> text("Invalid signature")
    end
  end

  @doc """
  POST /api/webhooks/bitbucket-cloud/notify
  Bitbucket Cloud push webhook. Extracts repository URL from payload.
  Requires webhook secret verification when GOCD_WEBHOOK_SECRET is set.
  """
  def bitbucket_cloud_notify(conn, params) do
    if verify_webhook_secret(conn) do
      case extract_bitbucket_cloud_url(params) do
        url when is_binary(url) and url != "" ->
          trigger_poll(url)
          conn |> put_status(:accepted) |> text("Accepted")

        _ ->
          conn |> put_status(:bad_request) |> text("Missing repository URL in payload")
      end
    else
      conn
      |> put_status(:unauthorized)
      |> text("Invalid signature")
    end
  end

  @doc """
  POST /api/admin/materials/hg/notify
  Mercurial post-commit hook.
  """
  def hg_notify(conn, params), do: admin_notify(conn, params)

  @doc """
  POST /api/admin/materials/other-scm/notify
  Generic SCM post-commit hook.
  """
  def other_scm_notify(conn, params), do: admin_notify(conn, params)

  # ── Admin-auth-protected admin notify (git, hg, other-scm) ────────────────
  # Requires a valid admin-role Bearer token. Mirrors GoCD's
  # MaterialNotifyControllerV2 which requires checkAdminUserAnd403.

  defp admin_notify(conn, params) do
    if admin_authenticated?(conn) do
      case Map.get(params, "repository_url") do
        url when is_binary(url) and url != "" ->
          trigger_poll(url)

          conn
          |> put_status(:accepted)
          |> json(%{
            "message" =>
              "The material is now scheduled for an update. Please check relevant pipeline(s) for status."
          })

        _ ->
          conn
          |> put_status(:bad_request)
          |> json(%{"error" => "Missing parameter 'repository_url'"})
      end
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{"error" => "Admin access token required"})
    end
  end

  defp admin_authenticated?(conn) do
    # GoCD open mode: no admin configured → anyone can trigger polling
    not ExGoCD.Accounts.admin_configured?() or
      conn
      |> Plug.Conn.get_session()
      |> ExGoCD.Accounts.get_current_user()
      |> ExGoCD.Accounts.User.has_role?(:admin)
  end

  # Shared webhook secret verifier for bitbucket endpoints
  defp verify_webhook_secret(conn) do
    case System.get_env("GOCD_WEBHOOK_SECRET") do
      nil ->
        true

      "" ->
        true

      secret ->
        # Bitbucket Server uses X-Hub-Signature header
        signature =
          List.first(get_req_header(conn, "x-hub-signature")) ||
            List.first(get_req_header(conn, "x-hub-signature-256"))

        if signature do
          expected =
            if String.starts_with?(signature, "sha256=") do
              "sha256=" <> expected_sig = signature
              raw_body = conn.assigns[:raw_body] || ""

              actual_sig =
                :crypto.mac(:hmac, :sha256, secret, raw_body) |> Base.encode16(case: :lower)

              Plug.Crypto.secure_compare(actual_sig, expected_sig)
            else
              raw_body = conn.assigns[:raw_body] || ""

              actual_sig =
                :crypto.mac(:hmac, :sha1, secret, raw_body) |> Base.encode16(case: :lower)

              Plug.Crypto.secure_compare(actual_sig, signature)
            end

          expected
        else
          false
        end
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

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

              actual_sig =
                :crypto.mac(:hmac, :sha256, secret, raw_body) |> Base.encode16(case: :lower)

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

  defp extract_bitbucket_server_url(params) do
    case params do
      %{"repository" => %{"links" => %{"clone" => clones}}} when is_list(clones) ->
        Enum.find_value(clones, fn
          %{"name" => "http", "href" => url} when is_binary(url) -> url
          %{"name" => "ssh", "href" => url} when is_binary(url) -> url
          _ -> nil
        end)

      %{"repository" => %{"links" => %{"self" => links}}} ->
        Enum.find_value(List.wrap(links), fn
          %{"href" => url} when is_binary(url) -> url
          _ -> nil
        end)

      _ ->
        nil
    end
  end

  defp extract_bitbucket_cloud_url(params) do
    case params do
      %{"repository" => %{"links" => %{"html" => %{"href" => url}}}} when is_binary(url) ->
        url

      %{"repository" => %{"full_name" => name}} when is_binary(name) ->
        "https://bitbucket.org/#{name}.git"

      _ ->
        nil
    end
  end
end
