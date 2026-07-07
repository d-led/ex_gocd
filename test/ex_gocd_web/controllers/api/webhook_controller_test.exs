defmodule ExGoCDWeb.API.WebhookControllerTest do
  use ExGoCDWeb.ConnCase, async: false

  alias ExGoCD.Accounts
  alias ExGoCD.Pipelines.{Job, Material, Modification, Pipeline, PipelineInstance, Stage, Task}
  alias ExGoCD.Repo
  import Ecto.Query

  setup %{conn: conn} do
    # Clean up DB before each test
    Repo.delete_all(Modification)
    Repo.delete_all(PipelineInstance)
    Repo.delete_all(Pipeline)
    Repo.delete_all(Material)

    # Clean up any admin users from other tests
    {:ok, _} =
      Ecto.Adapters.SQL.query(Repo, "DELETE FROM users WHERE username LIKE 'webhook_admin_%'")

    # Clean env variables
    System.delete_env("GOCD_WEBHOOK_SECRET")

    # Clear mock configuration revision
    Application.delete_env(:ex_gocd, :mock_git_revision)

    on_exit(fn ->
      Application.delete_env(:ex_gocd, :mock_git_revision)
    end)

    {:ok, conn: conn}
  end

  describe "POST /api/admin/materials/git/notify" do
    setup do
      # Create admin user so system is in security mode
      {:ok, admin} =
        Accounts.create_user(%{
          username: "webhook_admin_git",
          display_name: "Webhook Admin",
          roles: ["admin"],
          status: "Active"
        })

      {:ok, admin: admin}
    end

    test "returns 401 when no admin session", %{conn: conn} do
      conn =
        post(conn, ~p"/api/admin/materials/git/notify", %{
          "repository_url" => "https://github.com/d-led/ex_gocd"
        })

      assert json_response(conn, 401) == %{"error" => "Admin access token required"}
    end

    test "returns 400 when repository_url is missing (admin authenticated)", %{
      conn: conn,
      admin: admin
    } do
      conn =
        conn
        |> init_test_session(%{"username" => admin.username, "user_id" => admin.id})
        |> post(~p"/api/admin/materials/git/notify", %{})

      assert json_response(conn, 400) == %{"error" => "Missing parameter 'repository_url'"}
    end

    test "triggers polling and returns 202 with admin session", %{conn: conn, admin: admin} do
      seed_pipeline_with_stages("https://github.com/d-led/ex_gocd.git", "webhook-test-pipeline")

      # Mock revision in git client
      sha = "c0ffee5555555555555555555555555555555555"
      Application.put_env(:ex_gocd, :mock_git_revision, sha)

      conn =
        conn
        |> init_test_session(%{"username" => admin.username, "user_id" => admin.id})
        |> post(~p"/api/admin/materials/git/notify", %{
          "repository_url" => "https://github.com/d-led/ex_gocd"
        })

      assert response = json_response(conn, 202)

      assert response["message"] ==
               "The material is now scheduled for an update. Please check relevant pipeline(s) for status."

      # Polling is synchronous in test mode — DB is already updated
      assert Repo.exists?(from m in Modification, where: m.revision == ^sha)
    end
  end

  describe "POST /api/webhooks/github/notify" do
    test "returns 202 and triggers polling when webhook secret is not set", %{conn: conn} do
      seed_pipeline_with_stages("https://github.com/d-led/ex_gocd.git", "github-webhook-pipeline")

      sha = "c0ffee6666666666666666666666666666666666"
      Application.put_env(:ex_gocd, :mock_git_revision, sha)

      payload = %{
        "repository" => %{
          "clone_url" => "https://github.com/d-led/ex_gocd.git"
        }
      }

      conn = post(conn, ~p"/api/webhooks/github/notify", payload)
      assert response(conn, 202) == "Accepted"

      # Polling is synchronous in test mode
      assert Repo.exists?(from m in Modification, where: m.revision == ^sha)
    end

    test "validates HMAC signature when GOCD_WEBHOOK_SECRET is set", %{conn: conn} do
      System.put_env("GOCD_WEBHOOK_SECRET", "my_secret")
      seed_pipeline_with_stages("https://github.com/d-led/ex_gocd.git", "github-sig-pipeline")

      sha = "c0ffee8888888888888888888888888888888888"
      Application.put_env(:ex_gocd, :mock_git_revision, sha)

      payload = %{
        "repository" => %{
          "clone_url" => "https://github.com/d-led/ex_gocd.git"
        }
      }

      body = Phoenix.json_library().encode!(payload)

      # 1. Request with invalid signature
      conn_invalid =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-hub-signature-256", "sha256=invalid_signature")
        |> post(~p"/api/webhooks/github/notify", body)

      assert response(conn_invalid, 401) == "Invalid signature"

      # 2. Request with valid signature
      expected_sig = :crypto.mac(:hmac, :sha256, "my_secret", body) |> Base.encode16(case: :lower)

      conn_valid =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-hub-signature-256", "sha256=#{expected_sig}")
        |> post(~p"/api/webhooks/github/notify", body)

      assert response(conn_valid, 202) == "Accepted"

      # Polling is synchronous in test mode
      assert Repo.exists?(from m in Modification, where: m.revision == ^sha)
    end
  end

  describe "POST /api/webhooks/gitlab/notify" do
    test "returns 202 and triggers polling when webhook secret is not set", %{conn: conn} do
      seed_pipeline_with_stages("https://gitlab.com/d-led/ex_gocd.git", "gitlab-webhook-pipeline")

      sha = "c0ffee7777777777777777777777777777777777"
      Application.put_env(:ex_gocd, :mock_git_revision, sha)

      payload = %{
        "repository" => %{
          "git_http_url" => "https://gitlab.com/d-led/ex_gocd.git"
        }
      }

      conn = post(conn, ~p"/api/webhooks/gitlab/notify", payload)
      assert response(conn, 202) == "Accepted"

      # Polling is synchronous in test mode
      assert Repo.exists?(from m in Modification, where: m.revision == ^sha)
    end

    test "validates token when GOCD_WEBHOOK_SECRET is set", %{conn: conn} do
      System.put_env("GOCD_WEBHOOK_SECRET", "my_gitlab_secret")
      seed_pipeline_with_stages("https://gitlab.com/d-led/ex_gocd.git", "gitlab-token-pipeline")

      sha = "c0ffee9999999999999999999999999999999999"
      Application.put_env(:ex_gocd, :mock_git_revision, sha)

      payload = %{
        "repository" => %{
          "git_http_url" => "https://gitlab.com/d-led/ex_gocd.git"
        }
      }

      # 1. Request with invalid token
      conn_invalid =
        conn
        |> put_req_header("x-gitlab-token", "invalid_token")
        |> post(~p"/api/webhooks/gitlab/notify", payload)

      assert response(conn_invalid, 401) == "Invalid token"

      # 2. Request with valid token
      conn_valid =
        conn
        |> put_req_header("x-gitlab-token", "my_gitlab_secret")
        |> post(~p"/api/webhooks/gitlab/notify", payload)

      assert response(conn_valid, 202) == "Accepted"

      # Polling is synchronous in test mode
      assert Repo.exists?(from m in Modification, where: m.revision == ^sha)
    end
  end

  describe "POST /api/webhooks/bitbucket-server/notify" do
    test "returns 202 when webhook secret is not set", %{conn: conn} do
      seed_pipeline_with_stages(
        "https://bitbucket.org/myteam/myrepo.git",
        "bitbucket-server-pipeline"
      )

      sha = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
      Application.put_env(:ex_gocd, :mock_git_revision, sha)

      payload = %{
        "repository" => %{
          "links" => %{
            "clone" => [%{"name" => "http", "href" => "https://bitbucket.org/myteam/myrepo.git"}]
          }
        }
      }

      conn = post(conn, ~p"/api/webhooks/bitbucket-server/notify", payload)
      assert response(conn, 202) == "Accepted"
      assert Repo.exists?(from m in Modification, where: m.revision == ^sha)
    end

    test "returns 401 when webhook secret is set and signature is missing", %{conn: conn} do
      System.put_env("GOCD_WEBHOOK_SECRET", "bitbucket_secret")

      payload = %{
        "repository" => %{
          "links" => %{
            "clone" => [%{"name" => "http", "href" => "https://bitbucket.org/myteam/myrepo.git"}]
          }
        }
      }

      conn = post(conn, ~p"/api/webhooks/bitbucket-server/notify", payload)
      assert response(conn, 401) == "Invalid signature"
    end
  end

  describe "POST /api/webhooks/bitbucket-cloud/notify" do
    test "returns 202 when webhook secret is not set", %{conn: conn} do
      seed_pipeline_with_stages(
        "https://bitbucket.org/myteam/myrepo-cloud.git",
        "bitbucket-cloud-pipeline"
      )

      sha = "cccccccccccccccccccccccccccccccccccccccc"
      Application.put_env(:ex_gocd, :mock_git_revision, sha)

      payload = %{
        "repository" => %{
          "full_name" => "myteam/myrepo-cloud",
          "links" => %{
            "html" => %{"href" => "https://bitbucket.org/myteam/myrepo-cloud"}
          }
        }
      }

      conn = post(conn, ~p"/api/webhooks/bitbucket-cloud/notify", payload)
      assert response(conn, 202) == "Accepted"
      assert Repo.exists?(from m in Modification, where: m.revision == ^sha)
    end

    test "returns 401 when webhook secret is set and signature is missing", %{conn: conn} do
      System.put_env("GOCD_WEBHOOK_SECRET", "bitbucket_cloud_secret")

      payload = %{
        "repository" => %{
          "full_name" => "myteam/myrepo-cloud",
          "links" => %{
            "html" => %{"href" => "https://bitbucket.org/myteam/myrepo-cloud"}
          }
        }
      }

      conn = post(conn, ~p"/api/webhooks/bitbucket-cloud/notify", payload)
      assert response(conn, 401) == "Invalid signature"
    end
  end

  # Helper functions

  defp seed_pipeline_with_stages(url, name) do
    material =
      Repo.insert!(%Material{
        type: "git",
        url: url,
        branch: "master",
        auto_update: true
      })

    pipeline = Repo.insert!(%Pipeline{name: name, group: "default"})

    Repo.insert_all("pipelines_materials", [%{pipeline_id: pipeline.id, material_id: material.id}])

    # Add stage and job configurations
    stage = Repo.insert!(%Stage{name: "build-stage", pipeline_id: pipeline.id})
    job = Repo.insert!(%Job{name: "compile-job", stage_id: stage.id})
    Repo.insert!(%Task{type: "exec", command: "echo", arguments: ["building..."], job_id: job.id})

    {material, pipeline}
  end
end
