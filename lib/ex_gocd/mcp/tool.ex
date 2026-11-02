defmodule ExGoCD.Mcp.Tool do
  @moduledoc """
  What every tool shares: the shape of an answer, the context a tool cannot work
  out for itself, and the words the protocol's annotations are written with.

  A tool answers `{:ok, %{text: text, structured: structured}}` or
  `{:error, message}`. The text is what a model reads; the structured part is the
  same answer for a program that would rather not parse prose. The protocol layer
  turns the second form into a tool execution error, which is the specification's
  way of saying "this call failed, the message says how" rather than "the server
  is broken".
  """

  alias ExGoCD.Accounts.User

  @typedoc """
  Who is asking and where this server answers.

  `user` is resolved from the request's credentials by the same plug the JSON API
  uses, so a tool's permission checks are the API's checks. `base_url` is the
  address the caller used — a link in an answer must open on the server it was
  asked of, not on one from a config file.
  """
  @type ctx :: %{user: User.t(), base_url: String.t()}

  @typedoc "The two shapes a tool may answer with."
  @type result :: {:ok, %{text: String.t(), structured: map()}} | {:error, String.t()}

  @doc "An answer: the text a model reads, and the same facts as a map."
  @spec ok(String.t(), map()) :: result()
  def ok(text, structured), do: {:ok, %{text: text, structured: structured}}

  @doc "The annotations of a tool that only reads."
  @spec read_only() :: map()
  def read_only do
    %{
      "readOnlyHint" => true,
      "destructiveHint" => false,
      "idempotentHint" => true,
      "openWorldHint" => false
    }
  end

  @doc "The annotations of a tool that changes something, reversibly."
  @spec writes() :: map()
  def writes do
    %{
      "readOnlyHint" => false,
      "destructiveHint" => false,
      "idempotentHint" => false,
      "openWorldHint" => false
    }
  end

  @doc "The annotations of a tool that can throw work away."
  @spec destructive() :: map()
  def destructive do
    %{
      "readOnlyHint" => false,
      "destructiveHint" => true,
      "idempotentHint" => false,
      "openWorldHint" => false
    }
  end
end
