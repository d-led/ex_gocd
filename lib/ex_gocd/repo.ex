defmodule ExGoCD.Repo do
  use Ecto.Repo,
    otp_app: :ex_gocd,
    adapter: Ecto.Adapters.Postgres
end
