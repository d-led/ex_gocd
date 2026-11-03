defmodule ExGoCD.TestEnv do
  @moduledoc """
  Sets an application environment value for the length of one test and leaves the
  application as it was.

  `Application.put_env(:ex_gocd, key, previous)` is not the way back. When the key
  was never set, `Application.get_env/2` answers `nil`, and writing that `nil`
  back *creates* the key — so a long-lived process reading it afterwards gets
  `nil` where its default used to be. That is how the elastic agent scheduler came
  to call `nil.get_queue_state/0` on a tick after the suite had finished.
  """
  def replace(key, value) do
    previous = Application.get_env(:ex_gocd, key)
    Application.put_env(:ex_gocd, key, value)

    ExUnit.Callbacks.on_exit(fn -> restore(key, previous) end)
  end

  @doc """
  Puts back what `replace/2` found, where `nil` means the key was not set at all.
  """
  def restore(key, nil) do
    Application.delete_env(:ex_gocd, key)
    :ok
  end

  def restore(key, previous) do
    Application.put_env(:ex_gocd, key, previous)
    :ok
  end
end
