defmodule Rtc.FFmpegStreamer do
  use GenServer, restart: :transient

  alias Rtc.Env

  @moduledoc """
  Spawn a GenServer to handle the HLS and DASH streaming via FFMPEG transcoding.

  The GenServer will spawnPorcelain processes, which will run FFMEG to transcode the input stream into HLS and DASH formats and saved on the FileSystem.

  The GenServer implements a backpressure mechanism to avoid overloading the Porcelain processes with data with the `:queue` module.
  """

  defp id(type, user_id), do: type <> "-" <> to_string(user_id)
  defp via(type, user_id), do: {:via, Registry, {Rtc.Reg, id(type, user_id)}}

  def start_link([type: type, user_id: user_id] = args) do
    GenServer.start_link(__MODULE__, args, name: via(type, user_id))
  end

  def get_ffmpeg_pid(%{type: type, user_id: user_id}) do
    GenServer.call(via(type, user_id), :get_ffmpeg_pid)
  end

  def enqueue_path(%{type: type, user_id: user_id, path: path}) do
    GenServer.call(via(type, user_id), {:enqueue_path, type, path})
  end

  def pid(%{type: type, user_id: user_id}) do
    GenServer.call(via(type, user_id), :pid)
  end

  def init(args) do
    IO.puts("FFmpegStreamer **************")
    ffmpeg_os_path = Env.ffmpeg()

    playlist_path = Path.join(Env.hls_dir(), "stream.m3u8")
    segment_path = Path.join(Env.hls_dir(), "segment_%03d.ts")

    fps = Env.fps()

    hls_cmd =
      [
        ffmpeg_os_path,
        ["-loglevel", "debug"],
        # Input from stdin (pipe)
        ["-i", "pipe:0"],
        # sets the input frame rate to 20 frames per second.
        # Adjusted  to the value used in te browser
        ["-r", fps],
        # Video codec to use (libx264)
        ["-c:v", "libx264"],
        # Duration of each segment in seconds
        ["-hls_time", "2"],
        # Number of segments to keep in the playlist (rolling playlist)
        ["-hls_list_size", "5"],
        # Option to delete old segments
        ["-hls_flags", "delete_segments+append_list"],
        # Type of playlist (live for continuous update)
        ["-hls_playlist_type", "event"],
        # Segment file naming pattern
        ["-hls_segment_filename", segment_path],
        # Playlist file
        playlist_path
      ]
      |> List.flatten()

    # "-loglevel","warning"

    dash_path = Path.join(Env.dash_dir(), "stream.mpd")

    dash_cmd =
      [
        ffmpeg_os_path,
        ["-loglevel", "debug"],
        # Input from stdin
        ["-i", "-"],
        # Set the input frame rate to 20 fps
        ["-r", fps],
        # Use the libx264 codec for video encoding
        ["-c:v", "libx264"],
        # Enable timeline usage in DASH manifest, useful for seeking
        ["-use_timeline", "1"],
        # Enable template usage for segment and initialization file names
        # allowing for dynamic generation of these names based on specified patterns.
        ["-use_template", "1"],
        # Template for initialization segment name
        # specifies the template for the initialization segment name,
        # where $RepresentationID$ will be replaced with the actual representation ID.
        ["-init_seg_name", "init-$RepresentationID$.mp4"],
        # Template for media segment names
        # where $RepresentationID$ will be replaced
        # with the actual representation ID and $Number$ with the segment number.
        ["-media_seg_name", "chunk-$RepresentationID$-$Number$.m4s"],
        # Specify the output format as DASH
        ["-f", "dash"],
        # Output path for the DASH manifest (MPD) and segments will be stored
        dash_path
      ]
      |> List.flatten()

    ffmpeg_os_path = "/opt/homebrew/Cellar/ffmpeg/7.0-with-options_1/bin/ffmpeg"

    # echo_cmd = ~w(#{ffmpeg_os_path} -r #{fps}  -s 600x320 -i pipe:0 -c:v copy -f webm demo/test.webm )
    echo_cmd = ~w(#{ffmpeg_os_path} -f ivf  -i pipe:0 -c:v copy -f ivf -y demo/output.ivf)
    # [
    #   ffmpeg_os_path,
    #   ["-loglevel", "debug"],
    #   # Input from stdin
    #   ["-i", "-"],
    #   # Capture only the first frame
    #   ["-vframes", "1"],
    #   # Output format as an image pipe
    #   ["-f", "image2pipe"],
    #   # Use MJPEG codec for output
    #   ["-vcodec", "mjpeg"],
    #   # Overwrite output files without asking
    #   "-y",
    #   # Output to stdout
    #   "pipe:1"
    # ]
    # |> List.flatten()

    _evision_cmd =
      ~w(#{ffmpeg_os_path}  -loglevel debug -i - -f image2pipe -framerate 25 -c:v libx264 -pix_fmt yuv420p output.mp4)

    state =
      cond do
        args[:type] in ["hls", "face"] ->
          {:ok, ffmpeg_pid} = ExCmd.Process.start_link(hls_cmd)
          %{ffmpeg_pid: ffmpeg_pid}

        args[:type] == "evision" ->
          IO.puts("STARTED EVISION FFMPEG-------")
          %{}

        args[:type] == "dash" ->
          {:ok, ffmpeg_pid} = ExCmd.Process.start_link(dash_cmd)

          %{ffmpeg_pid: ffmpeg_pid}

        args[:type] in ["frame", "echo"] ->
          {:ok, ffmpeg_pid} = ExCmd.Process.start_link(echo_cmd, log: true)
          %{ffmpeg_pid: ffmpeg_pid}
      end
      |> Map.merge(%{type: args[:type], queue: :queue.new()})

    Process.link(state.ffmpeg_pid)

    {:ok, state}
  end

  # for test only echo, called by test controller
  def handle_call(:get_ffmpeg_pid, _from, state) do
    {:reply, state.ffmpeg_pid, state}
  end

  def handle_call(:pid, _from, state) do
    {:reply, self(), state}
  end

  def handle_call({:enqueue_path, type, path}, _, state) do
    send(self(), {type, path})
    {:reply, :enqueued, state}
  end

  def handle_info(:ffmpeg_pid, state) do
    {:noreply, state}
  end

  def handle_info({"frame", frame}, state) do
    new_queue = :queue.in(frame, state.queue)
    send(self(), :process_frame_queue)
    {:noreply, %{state | queue: new_queue}}
  end

  def handle_info(:process_frame_queue, state) do
    case :queue.out(state.queue) do
      {{:value, frame}, new_queue} ->
        stream =
          ExCmd.stream!(
            ~w(#{state.ffmpeg_path} -i pipe:0 -frames:v 1 -f image2 -vcodec mjpeg -y pipe:1),
            input: File.stream!(frame, 65_336)
          )
          |> Enum.into("")

        Rtc.Processor.process_frame(stream, "priv/static/hls/test.jpg")

        send(self(), :process_frame_queue)
        {:noreply, %{state | queue: new_queue}}

      {:empty, _} ->
        {:noreply, state}
    end
  end

  # face----------------
  def handle_info({"face", path}, state) do
    new_queue = :queue.in(path, state.queue)
    send(self(), :process_face_queue)
    {:noreply, %{state | queue: new_queue}}
  end

  def handle_info(:process_face_queue, state) do
    case :queue.out(state.queue) do
      {{:value, path}, new_queue} ->
        ExCmd.Process.write(state.ffmpeg_pid, File.read!(path))
        send(self(), :process_face_queue)
        {:noreply, %{state | queue: new_queue}}

      {:empty, _} ->
        {:noreply, state}
    end
  end

  # for HLS---------------------
  def handle_info({"hls", path}, state) do
    new_queue = :queue.in(path, state.queue)
    send(self(), :process_hls_queue)
    {:noreply, %{state | queue: new_queue}}
  end

  def handle_info(:process_hls_queue, state) do
    case :queue.out(state.queue) do
      {{:value, path}, new_queue} ->
        ExCmd.Process.write(state.ffmpeg_pid, File.read!(path))
        send(self(), :process_hls_queue)
        {:noreply, %{state | queue: new_queue}}

      {:empty, _} ->
        IO.puts("Processed------")
        {:noreply, state}
    end
  end

  def handle_info({:stop, type}, %{ffmpeg_pid: pid} = state) when type in ["hls", "face"] do
    :ok = ExCmd.Process.close_stdin(pid)
    :eof = ExCmd.Process.read(pid)
    {:ok, 0} = ExCmd.Process.await_exit(pid)
    {:stop, :shutdown, state}
  end

  # for dash---------------------
  def handle_info({"dash", data}, state) do
    new_queue = :queue.in(data, state.queue)
    send(self(), :process_dash_queue)
    {:noreply, %{state | queue: new_queue}}
  end

  def handle_info(:process_dash_queue, state) do
    case :queue.out(state.queue) do
      {{:value, _data}, new_queue} ->
        {:noreply, %{state | dash_queue: new_queue}}

      {:empty, _} ->
        {:noreply, state}
    end
  end

  def handle_info({:stop, "dash"}, state) do
    ExCmd.Process.stop(state.ffmpeg_pid)
    {:stop, :shutdown, state}
  end

  # for echo ------
  def handle_info({"echo", _data, _sender_pid}, state) do
    # DO SOMETHING ????
    {:noreply, state}
  end
end
