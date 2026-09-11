defmodule MikeosServidor.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MikeosServidorWeb.Telemetry,
      MikeosServidor.Repo,
      {DNSCluster, query: Application.get_env(:mikeos_servidor, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: MikeosServidor.PubSub},
      # Lee repo.json cada pocos minutos para responder /api/version sin tocar
      # el disco en cada petición.
      MikeosServidor.Catalogo,
      # Start a worker by calling: MikeosServidor.Worker.start_link(arg)
      # {MikeosServidor.Worker, arg},
      # Start to serve requests, typically the last entry
      MikeosServidorWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MikeosServidor.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MikeosServidorWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
