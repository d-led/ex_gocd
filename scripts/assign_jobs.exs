import Ecto.Query
alias ExGoCD.{Repo, Scheduler}

agent = Repo.one(from a in ExGoCD.Agents.Agent, where: a.state == "Idle", limit: 1)
IO.inspect({agent.uuid, agent.resources}, label: "Docker agent")

result = Scheduler.try_assign_work(agent.uuid)
IO.inspect(result, label: "Assign result")
