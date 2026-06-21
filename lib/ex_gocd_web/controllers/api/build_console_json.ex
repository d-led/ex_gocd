defmodule ExGoCDWeb.API.BuildConsoleJSON do
  def error_404(_assigns), do: %{error: "run not found"}
  def error_413(_assigns), do: %{error: "payload too large"}
end
