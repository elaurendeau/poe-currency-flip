defmodule PoeFlipFinder.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  # The OTP composition root: it's allowed to see both Core and Web because
  # wiring them together into one supervision tree is exactly what
  # "Frameworks & Drivers" (the outermost ring) is for. Neither Core nor Web
  # depend on this module.
  use Boundary, deps: [PoeFlipFinder, PoeFlipFinderWeb], top_level?: true

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PoeFlipFinderWeb.Telemetry,
      PoeFlipFinder.Repo,
      {DNSCluster, query: Application.get_env(:poe_flip_finder, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: PoeFlipFinder.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: PoeFlipFinder.Finch},
      # Start a worker by calling: PoeFlipFinder.Worker.start_link(arg)
      # {PoeFlipFinder.Worker, arg},
      # Start to serve requests, typically the last entry
      PoeFlipFinderWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: PoeFlipFinder.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PoeFlipFinderWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
