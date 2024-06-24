defmodule Rtc.FFmpegStreamer do
  use GenServer, restart: :transient

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

  def get_data(%{type: type, user_id: user_id}) do
    GenServer.call(via(type, user_id), :get_data)
  end

  def process_hls_chunk(%{type: type, user_id: user_id, chunk: chunk}) do
    GenServer.call(via(type, user_id), {:process_hls_chunk, chunk})
  end

  def pid(%{type: type, user_id: user_id}) do
    GenServer.call(via(type, user_id), :pid)
  end

  def init(args) do
    ffmpeg = Application.fetch_env!(:rtc, :ffmpeg)
    hls_dir = Application.fetch_env!(:rtc, :hls)[:hls_dir]
    dash_dir = Application.fetch_env!(:rtc, :hls)[:dash_dir]

    playlist = Path.join(hls_dir, "stream.m3u8")
    segment = Path.join(hls_dir, "segment_%03d.ts")

    hls_cmd =
      [
        # Input from stdin (pipe)
        ["-i", "pipe:0"],
        # sets the input frame rate to 20 frames per second.
        # Adjusted  to the value used in te browser
        ["-r", "20"],
        # Video codec to use (libx264)
        ["-c:v", "libx264"],
        # Duration of each segment in seconds
        ["-hls_time", "2"],
        # Number of segments to keep in the playlist (rolling playlist)
        ["-hls_list_size", "5"],
        # Option to delete old segments
        ["-hls_flags", "delete_segments"],
        # Type of playlist (live for continuous update)
        ["-hls_playlist_type", "event"],
        # Segment file naming pattern
        ["-hls_segment_filename", segment],
        # Playlist file
        playlist
      ]
      |> List.flatten()

    # "-loglevel","warning"

    dash_path = dash_dir <> "stream.mpd"

    dash_cmd =
      [
        # Input from stdin
        ["-i", "-"],
        # Set the input frame rate to 20 fps
        ["-r", "20"],
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

    echo_cmd =
      [
        # Input from stdin
        ["-i", "-"],
        # Capture only the first frame
        ["-frames:v", "1"],
        # Output format as an image pipe
        ["-f", "image2pipe"],
        # Use MJPEG codec for output
        ["-vcodec", "mjpeg"],
        # Overwrite output files without asking
        "-y",
        # Output to stdout
        "pipe:1"
      ]
      |> List.flatten()

    state =
      cond do
        args[:type] in ["hls", "face"] ->
          %{
            porcelain_hls: Porcelain.spawn(ffmpeg, hls_cmd, in: :receive, out: :stream),
            cmd: hls_cmd,
            path: hls_dir
          }

        args[:type] == "dash" ->
          %{
            porcelain_dash: Porcelain.spawn(ffmpeg, dash_cmd, in: :receive, out: :stream),
            cmd: dash_cmd,
            path: dash_dir
          }

        args[:type] == "echo" ->
          %{
            porcelain_echo: Porcelain.spawn(ffmpeg, echo_cmd, in: :receive, out: :stream),
            cmd: echo_cmd
          }
      end

    # state =
    #   case args[:type] do
    #     "hls" ->
    #       %{
    #         porcelain_hls: Porcelain.spawn(ffmpeg, hls_cmd, in: :receive, out: :stream),
    #         # porcelain_hls: nil,
    #         cmd: echo_cmd,
    #         path: hls_dir
    #       }

    #     "dash" ->
    #       %{
    #         porcelain_dash: Porcelain.spawn(ffmpeg, dash_cmd, in: :receive, out: :stream),
    #         cmd: dash_cmd,
    #         path: dash_dir
    #       }

    #     "echo" ->
    #       %{
    #         porcelain_echo: Porcelain.spawn(ffmpeg, echo_cmd, in: :receive, out: :stream),
    #         cmd: echo_cmd
    #       }
    #   end

    # this is for test echo only to get the first frame
    state = Map.merge(state, %{type: args[:type], ffmpeg: ffmpeg, queue: :queue.new()})

    {:ok, state}
  end

  # for test only echo, called by test controller
  def handle_call(:get_data, _from, state) do
    {:reply, state.data, state}
  end

  def handle_call(:pid, _from, state) do
    {:reply, self(), state}
  end

  # for HLS---------------------
  def handle_call({:process_hls_chunk, chunk}, _, state) do
    send(self(), {"hls", chunk})
    {:reply, :processed, state}
  end

  def handle_info({"hls", data}, state) do
    new_queue = :queue.in(data, state.queue)
    send(self(), :process_hls_queue)
    {:noreply, %{state | queue: new_queue}}
  end

  def handle_info(:process_hls_queue, state) do
    case :queue.out(state.queue) do
      {{:value, data}, new_queue} ->
        Porcelain.Process.send_input(state.porcelain_hls, data)

        # {:ok, tmp_file} = Plug.Upload.random_file("jpeg") |> dbg()

        # ExCmd.stream!(~w(#{state.ffmpeg} #{state.cmd}), input: File.stream!(data))
        # |> Stream.into(File.stream!(tmp_file))
        # |> Stream.run()

        # %Plug.Upload{path: path} = data
        # ExCmd.stream!(~w(#{state.ffmpeg} #{state.hls_cmd}),
        #   input: File.stream!(path)
        # )

        {:noreply, %{state | queue: new_queue}}

      {:empty, _} ->
        {:noreply, state}
    end
  end

  def handle_info({:stop, type}, state) when type in ["hls", "face"] do
    Porcelain.Process.signal(state.porcelain_hls, :kill)
    Porcelain.Process.stop(state.porcelain_hls)

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
      {{:value, data}, new_queue} ->
        Porcelain.Process.send_input(state.porcelain_dash, data)
        {:noreply, %{state | dash_queue: new_queue}}

      {:empty, _} ->
        {:noreply, state}
    end
  end

  def handle_info({:stop, "dash"}, state) do
    Porcelain.Process.stop(state.porcelain_dash)
    {:stop, :shutdown, state}
  end

  # for echo ------
  def handle_info({"echo", _data, _sender_pid}, state) do
    # DO SOMETHING ????
    {:noreply, state}
  end

  def handle_info({:echo, _data, _sender_pid}, state) do
    {:noreply, state}
  end
end
