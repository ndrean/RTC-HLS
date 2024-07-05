defmodule Rtc.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Rtc.Env

  def ensure_dir do
    File.mkdir(Env.hls_dir())
    File.mkdir(Env.dash_dir())
    {:error, _} = File.mkdir(Env.models_dir())
  end

  @impl true
  def start(_type, _args) do
    Env.init()
    ensure_dir()

    children = [
      RtcWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:rtc, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Rtc.PubSub},
      {Task.Supervisor, name: Rtc.TaskSup},
      {Registry, keys: :unique, name: Rtc.Reg, timeout: :infinity},
      {DynamicSupervisor, name: Rtc.DynSup, strategy: :one_for_one},
      {Rtc.FileCleaner, [every: Application.get_env(:rtc, :hls)[:every]]},
      Rtc.PeriodicCleaner,
      RtcWeb.Presence,
      Rtc.Lobby,
      {FileWatcher,
       [
         watch_dir: Env.hls_dir(),
         output_dir: Application.fetch_env!(:rtc, :hls)[:tmp_dir],
         playlist_path: Env.hls_dir()
       ]},
      RtcWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Rtc.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    RtcWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
