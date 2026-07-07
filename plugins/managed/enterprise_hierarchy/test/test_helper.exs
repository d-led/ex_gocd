ExUnit.start()

case GenServer.start_link(EnterpriseHierarchy, [], name: EnterpriseHierarchy) do
  {:ok, _pid} -> :ok
  {:error, {:already_started, _pid}} -> :ok
end
