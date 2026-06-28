defmodule ExGoCD.Mailer do
  @moduledoc """
  Email delivery via Swoosh for stage/pipeline notifications.

  Dev:  SMTP → smtp4dev (localhost:2525, web UI at localhost:8025)
  Test: Swoosh.Adapters.Test (no real delivery)
  Prod: configured via SMTP_* env vars
  """
  use Swoosh.Mailer, otp_app: :ex_gocd

  alias Swoosh.Email

  @from {"ex_gocd", "noreply@exgocd.local"}

  @doc "Sends a stage event notification email."
  def stage_notification(user_email, pipeline_name, stage_name, event, result) do
    subject = "[#{pipeline_name}] #{stage_name} #{event} — #{result}"

    %Email{}
    |> Email.from(@from)
    |> Email.to(user_email)
    |> Email.subject(subject)
    |> Email.text_body(body(pipeline_name, stage_name, event, result))
    |> deliver()
  end

  defp body(pipeline_name, stage_name, event, result) do
    """
    Pipeline: #{pipeline_name}
    Stage:    #{stage_name}
    Event:    #{event}
    Result:   #{result}

    This is an automated notification from ex_gocd.
    """
  end
end
