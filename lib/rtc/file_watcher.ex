defmodule FileWatcher do
  alias Phoenix.PubSub
  use GenServer
  # alias Rtc.SegmentProcessor

  @moduledoc """
  Watching HLS segments and playlist
  """

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    watch_dir = opts[:watch_dir] || raise "watch_dir not provided"
    output_dir = opts[:output_dir] || raise "output_dir not provided"
    playlist_path = opts[:playlist_path] || raise "playlist_path not provided"

    {:ok, watcher_pid} = FileSystem.start_link(dirs: [watch_dir])
    FileSystem.subscribe(watcher_pid)

    state = %{
      watcher_pid: watcher_pid,
      watch_dir: watch_dir,
      output_dir: output_dir,
      playlist_path: playlist_path,
      queue: :queue.new(),
      processed_files: MapSet.new()
    }

    {:ok, state}
  end

  def handle_info({:file_event, _pid, {path, [:renamed]}}, state) do
    # warn the LiveView that the HLS stream is ready
    if Path.extname(path) == ".m3u8",
      do: PubSub.broadcast(Rtc.PubSub, "hls:m3u8", :playlist_ready)

    {:noreply, state}
  end

  def handle_info({:file_event, _watcher_pid, {path, events}}, state) do
    if Path.extname(path) == ".ts" and (:created in events or :modified in events) do
      if MapSet.member?(state.processed_files, path) == false do
        state = enqueue_segment(path, state)
        {:noreply, process_queue(state)}
      else
        {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  defp enqueue_segment(path, state) do
    new_queue = :queue.in(path, state.queue)
    %{state | queue: new_queue}
  end

  defp process_queue(state) do
    case :queue.out(state.queue) do
      {{:value, segment_path}, new_queue} ->
        # SegmentProcessor.process_segment(segment_path, state.output_dir)
        # update_playlist(state.playlist_path, state.output_dir)
        new_processed_files = MapSet.put(state.processed_files, segment_path)
        process_queue(%{state | queue: new_queue, processed_files: new_processed_files})

      {:empty, _queue} ->
        state
    end
  end

  defp update_playlist(playlist_path, output_dir) do
    segments =
      File.ls!(output_dir)
      |> Enum.filter(&String.ends_with?(&1, ".ts"))
      |> Enum.sort()

    File.write!(playlist_path, generate_playlist_content(segments))
  end

  defp generate_playlist_content(segments) do
    """
    #EXTM3U
    #EXT-X-VERSION:3
    #EXT-X-TARGETDURATION:10
    #EXT-X-MEDIA-SEQUENCE:0
    """ <>
      Enum.map_join(segments, "\n", fn segment ->
        """
        #EXTINF:10.0,
        #{segment}
        """
      end) <>
      "\n#EXT-X-ENDLIST"
  end
end
