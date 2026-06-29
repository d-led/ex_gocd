defmodule ExGoCD.Mailer do
  @moduledoc """
  Email delivery via Swoosh for stage/pipeline notifications.

  Mirrors GoCD's StageNotificationService + SendEmailMessage.
  Multipart: HTML (beautiful card) + plain-text (GoCD-parity format).

  Dev:  SMTP → smtp4dev (localhost:2525, web UI at localhost:8025)
  Test: Swoosh.Adapters.Test (no real delivery)
  Prod: configured via SMTP_* env vars
  """
  use Swoosh.Mailer, otp_app: :ex_gocd

  alias Swoosh.Email

  # Read from config. Defaults in config/config.exs.
  defp from do
    Application.get_env(:ex_gocd, :mailer_from, {"ex_gocd", "noreply@exgocd.local"})
  end

  defp site_url do
    Application.get_env(:ex_gocd, :site_url, "http://localhost:4000")
  end

  @doc """
  Sends a stage event notification email with GoCD-parity format.

  Options:
    - pipeline_counter, stage_counter: for detail links
    - triggered_by: who triggered it
    - materials: list of %{type: _, url: _, revision: _, user: _, date: _, comment: _}
  """
  def stage_notification(user_email, opts) do
    pipeline_name = opts[:pipeline_name]
    stage_name = opts[:stage_name]
    event = opts[:event] || "Unknown"
    result = opts[:result] || "Unknown"
    pipeline_counter = opts[:pipeline_counter]
    stage_counter = opts[:stage_counter]
    triggered_by = opts[:triggered_by]
    materials = opts[:materials] || []

    subject = subject_line(pipeline_name, stage_name, event, stage_counter)

    %Email{}
    |> Email.from(from())
    |> Email.to(user_email)
    |> Email.subject(subject)
    |> Email.html_body(
      html_body(
        pipeline_name,
        stage_name,
        event,
        result,
        pipeline_counter,
        stage_counter,
        triggered_by,
        materials
      )
    )
    |> Email.text_body(
      text_body(
        pipeline_name,
        stage_name,
        event,
        result,
        pipeline_counter,
        stage_counter,
        triggered_by,
        materials
      )
    )
    |> deliver()
  end

  # ── Subject (GoCD parity: "Stage [pipeline/stage/counter] Failed") ──────

  defp subject_line(pipeline_name, stage_name, event, stage_counter) do
    locator =
      if stage_counter,
        do: "#{pipeline_name}/#{stage_name}/#{stage_counter}",
        else: "#{pipeline_name}/#{stage_name}"

    "Stage [#{locator}] #{event}"
  end

  # ── HTML body ────────────────────────────────────────────────────────────

  defp html_body(pipeline, stage, event, result, p_ctr, s_ctr, triggered_by, materials) do
    event_color = event_color(event, result)
    detail_url = stage_detail_url(pipeline, p_ctr, stage, s_ctr)

    """
    <!DOCTYPE html>
    <html>
    <head><meta charset="utf-8"><meta name="viewport" content="width=device-width"></head>
    <body style="margin:0;padding:0;background:#f4f5f7;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif">
      <table width="100%" cellpadding="0" cellspacing="0" style="background:#f4f5f7;padding:24px 0">
        <tr><td align="center">
          <table width="600" cellpadding="0" cellspacing="0" style="background:#fff;border-radius:8px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,0.08)">

            <!-- Header -->
            <tr>
              <td style="background:#{event_color};padding:24px 32px">
                <table width="100%" cellpadding="0" cellspacing="0">
                  <tr>
                    <td style="font-size:13px;color:rgba(255,255,255,0.85);text-transform:uppercase;letter-spacing:0.5px;padding-bottom:6px">
                      #{event_icon(event, result)} #{event} &middot; #{result}
                    </td>
                  </tr>
                  <tr>
                    <td style="font-size:20px;font-weight:700;color:#fff">
                      #{pipeline} &rsaquo; #{stage}
                    </td>
                  </tr>
                  #{if p_ctr && s_ctr do
      """
      <tr>
        <td style="font-size:13px;color:rgba(255,255,255,0.75);padding-top:4px">
          ##{p_ctr} / #{stage} ##{s_ctr}
        </td>
      </tr>
      """
    end}
                </table>
              </td>
            </tr>

            <!-- Details -->
            <tr><td style="padding:24px 32px">

              #{if triggered_by do
      """
      <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:20px;border:1px solid #e5e7eb;border-radius:6px">
        <tr>
          <td style="padding:12px 16px;font-size:13px;color:#6b7280">
            Triggered by <strong style="color:#374151">#{triggered_by}</strong>
          </td>
        </tr>
      </table>
      """
    end}

              #{if detail_url do
      """
      <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:24px">
        <tr><td align="center">
          <a href="#{detail_url}" target="_blank" style="display:inline-block;background:#3b82f6;color:#fff;text-decoration:none;padding:10px 28px;border-radius:6px;font-size:14px;font-weight:600">
            View Stage Details &rarr;
          </a>
        </td></tr>
      </table>
      """
    end}

              #{if materials != [] do
      material_changes_html(materials)
    end}

            </td></tr>

            <!-- Footer -->
            <tr>
              <td style="background:#f9fafb;padding:16px 32px;border-top:1px solid #e5e7eb">
                <p style="margin:0;font-size:12px;color:#9ca3af">
                  Sent by ex_gocd &middot; <a href="#{site_url()}" style="color:#3b82f6;text-decoration:none">#{site_url()}</a>
                </p>
              </td>
            </tr>
          </table>
        </td></tr>
      </table>
    </body>
    </html>
    """
  end

  defp material_changes_html(materials) do
    header = """
    <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:16px">
      <tr>
        <td style="padding-bottom:8px;font-size:12px;font-weight:700;color:#6b7280;text-transform:uppercase;letter-spacing:0.5px;border-bottom:2px solid #e5e7eb">
          &#x1F504; Changes
        </td>
      </tr>
    </table>
    """

    rows =
      materials
      |> Enum.map(fn m ->
        """
        <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:16px;border:1px solid #e5e7eb;border-radius:6px">
          <tr>
            <td style="padding:14px 16px">
              <table width="100%" cellpadding="0" cellspacing="0">
                <tr>
                  <td style="font-size:12px;font-weight:600;color:#374151;padding-bottom:4px">
                    <span style="display:inline-block;background:#f3f4f6;padding:2px 8px;border-radius:4px">#{m[:type] || "Material"}</span>
                    &nbsp; #{m[:url] || ""}
                  </td>
                </tr>
                <tr>
                  <td style="font-size:13px;color:#6b7280;padding-bottom:2px">
                    Revision <code style="background:#f3f4f6;padding:1px 4px;border-radius:3px;font-size:12px">#{m[:revision] || "?"}</code>
                    by <strong style="color:#374151">#{m[:user] || "unknown"}</strong>
                    #{if m[:date], do: "on #{m[:date]}", else: ""}
                  </td>
                </tr>
                #{if m[:comment] && m[:comment] != "" do
          """
          <tr>
            <td style="font-size:13px;color:#374151;font-style:italic;padding-top:4px">
              #{m[:comment]}
            </td>
          </tr>
          """
        end}
              </table>
            </td>
          </tr>
        </table>
        """
      end)
      |> Enum.join("")

    header <> rows
  end

  # ── Plain-text body (GoCD parity) ────────────────────────────────────────

  defp text_body(pipeline, stage, _event, _result, p_ctr, s_ctr, triggered_by, materials) do
    detail_url = stage_detail_url(pipeline, p_ctr, stage, s_ctr)

    parts =
      [
        if(detail_url, do: "See details: #{detail_url}", else: nil),
        if(triggered_by, do: "Triggered by #{triggered_by}", else: nil),
        if(materials != [], do: material_changes_text(materials), else: nil),
        "Sent by ex_gocd"
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n\n")

    parts
  end

  defp material_changes_text(materials) do
    header = "-- CHANGES --"

    body =
      materials
      |> Enum.map(fn m ->
        """
        #{m[:type] || "Material"}: #{m[:url] || ""}
        revision: #{m[:revision] || "?"}, modified by #{m[:user] || "unknown"}#{if m[:date], do: " on #{m[:date]}", else: ""}
        #{m[:comment] || ""}\
        """
      end)
      |> Enum.join("\n\n")

    header <> "\n\n" <> body
  end

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp stage_detail_url(_pipeline, nil, _stage, _s_ctr), do: nil
  defp stage_detail_url(_pipeline, _p_ctr, _stage, nil), do: nil

  defp stage_detail_url(pipeline, p_ctr, stage, s_ctr) do
    "#{site_url()}/pipelines/#{pipeline}/#{p_ctr}/#{stage}/#{s_ctr}"
  end

  defp event_color("Passes", _), do: "22c55e"
  defp event_color("Fixed", _), do: "22c55e"
  defp event_color("Fails", _), do: "ef4444"
  defp event_color("Breaks", _), do: "ef4444"
  defp event_color("Cancelled", _), do: "f59e0b"
  defp event_color(_, "Passed"), do: "22c55e"
  defp event_color(_, "Failed"), do: "ef4444"
  defp event_color(_, "Cancelled"), do: "f59e0b"
  defp event_color(_, _), do: "6b7280"

  defp event_icon("Passes", _), do: "&#x2705;"
  defp event_icon("Fixed", _), do: "&#x2705;"
  defp event_icon("Fails", _), do: "&#x274C;"
  defp event_icon("Breaks", _), do: "&#x274C;"
  defp event_icon("Cancelled", _), do: "&#x26A0;"
  defp event_icon(_, "Passed"), do: "&#x2705;"
  defp event_icon(_, "Failed"), do: "&#x274C;"
  defp event_icon(_, _), do: "&#x2139;"
end
