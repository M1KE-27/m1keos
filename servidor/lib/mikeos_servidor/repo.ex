defmodule MikeosServidor.Repo do
  use Ecto.Repo,
    otp_app: :mikeos_servidor,
    adapter: Ecto.Adapters.Postgres
end
