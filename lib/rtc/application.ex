defmodule Rtc.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def ensure_dir do
    if {:error, :eexist} ==
         Application.fetch_env!(:rtc, :hls)[:hls_dir]
         |> File.mkdir() and
         {:error, :eexist} ==
           Application.fetch_env!(:rtc, :hls)[:dash_dir]
           |> File.mkdir(),
       do: :ok,
       else: :error
  end

  @impl true
  def start(_type, _args) do
    # Application.get_all_env(:rtc) |> dbg()
    :ok = ensure_dir()

    children = [
      RtcWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:rtc, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Rtc.PubSub},
      {Task.Supervisor, name: Rtc.TaskSup},
      {Registry, keys: :unique, name: Rtc.Reg, timeout: :infinity},
      {DynamicSupervisor, name: Rtc.DynSup, strategy: :one_for_one},
      {Rtc.FileCleaner, [every: Application.get_env(:rtc, :hls)[:every]]},
      Rtc.HlsPeriodicCleaner,
      RtcWeb.Presence,
      Rtc.Lobby,
      {FileWatcher,
       [
         watch_dir: Application.fetch_env!(:rtc, :hls)[:hls_dir],
         output_dir: Application.fetch_env!(:rtc, :hls)[:tmp_dir],
         playlist_path: Application.fetch_env!(:rtc, :hls)[:hls_dir]
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
