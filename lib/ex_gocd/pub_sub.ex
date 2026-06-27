defmodule ExGoCD.PubSub do
  @moduledoc """
  Central PubSub for live view updates.

  ## Topics
    #{@pipeline_topic} — pipeline/ stage/ job state changes
    #{@agent_topic} — agent registration, state, enable/disable
  """

  @pipeline_topic "pipelines:updates"
  @agent_topic "agents:updates"

  def pipeline_topic, do: @pipeline_topic
  def agent_topic, do: @agent_topic

  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(topic) do
    Phoenix.PubSub.subscribe(ExGoCD.PubSub, topic)
  end

  @spec broadcast(String.t(), term()) :: :ok | {:error, term()}
  def broadcast(topic, payload) do
    Phoenix.PubSub.broadcast(ExGoCD.PubSub, topic, payload)
  end

  @spec broadcast_pipeline(term()) :: :ok | {:error, term()}
  def broadcast_pipeline(payload) do
    broadcast(@pipeline_topic, payload)
  end

  @spec broadcast_agent(term()) :: :ok | {:error, term()}
  def broadcast_agent(payload) do
    broadcast(@agent_topic, payload)
  end
end
