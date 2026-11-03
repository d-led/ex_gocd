defmodule ExGoCD.TestEnvTest do
  @moduledoc """
  The application environment is global, so these run alone — and the point of
  them is the difference between "was never set" and "was set to nil", which is
  what left the elastic agent scheduler calling a function on `nil`.
  """
  use ExUnit.Case, async: false

  @key :test_env_probe

  setup do
    on_exit(fn -> Application.delete_env(:ex_gocd, @key) end)
    :ok
  end

  test "restoring a key that was never set leaves it unset" do
    Application.put_env(:ex_gocd, @key, :value)

    ExGoCD.TestEnv.restore(@key, nil)

    assert Application.fetch_env(:ex_gocd, @key) == :error
  end

  test "restoring a value that was there puts it back" do
    Application.put_env(:ex_gocd, @key, :overridden)

    ExGoCD.TestEnv.restore(@key, :original)

    assert Application.get_env(:ex_gocd, @key) == :original
  end
end
