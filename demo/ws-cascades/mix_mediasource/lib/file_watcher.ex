defmodule FileWatcher do
  use GenServer

  require Logger

  @impl true
  def init(ws_pid) do
    {:ok, watcher_pid} = FileSystem.start_link(dirs: ["priv/hls"])
    FileSystem.subscribe(watcher_pid)
    
    {:ok, %{watcher_pid: watcher_pid, ws_pid: ws_pid}}
  end

  @impl true
  def handle_info({:file_event, watcher_pid, {path, _}}, %{watcher_pid: watcher_pid, ws_pid: ws_pid} = state) do
    Logger.debug("File created: #{path}")
    if Path.extname(path) == ".m3u8", do:
      send(ws_pid, :playlist_created)
    {:noreply,state}
  end
end