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

  # def process_hls_path(%{type: type, user_id: user_id, file_path: path}) do
  #   GenServer.call(via(type, user_id), {:process_hls_path, path})
  # end

  def enqueue_path(%{type: type, user_id: user_id, path: path}) do
    GenServer.call(via(type, user_id), {:enqueue_path, type, path})
  end

  # def process_frame_path(%{type: type, user_id: user_id, frame_path: frame_path}) do
  #   GenServer.call(via(type, user_id), {:process_frame_path, frame_path})
  # end

  def pid(%{type: type, user_id: user_id}) do
    GenServer.call(via(type, user_id), :pid)
  end

  def init(args) do
    IO.puts("FFmpegStreamer **************")
    ffmpeg_os_path = Application.fetch_env!(:rtc, :ffmpeg) |> dbg()
    hls_dir = Application.fetch_env!(:rtc, :hls)[:hls_dir]
    dash_dir = Application.fetch_env!(:rtc, :hls)[:dash_dir]

    playlist_path = Path.join(hls_dir, "stream.m3u8")
    segment_path = Path.join(hls_dir, "segment_%03d.ts")

    hls_cmd =
      [
        ffmpeg_os_path,
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
        ["-hls_segment_filename", segment_path],
        ["-loglevel", "debug"],
        # Playlist file
        playlist_path
      ]
      |> List.flatten()

    # "-loglevel","warning"

    dash_path = dash_dir <> "stream.mpd"

    dash_cmd =
      [
        ffmpeg_os_path,
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
        ffmpeg_os_path,
        ["-loglevel", "debug"],
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

    _evision_cmd =
      ~w(#{ffmpeg_os_path} -i - -f image2pipe -framerate 25 -c:v libx264 -pix_fmt yuv420p output.mp4)

    state =
      cond do
        args[:type] in ["hls", "face"] ->
          {:ok, ffmpeg_pid} = ExCmd.Process.start_link(hls_cmd) |> dbg()

          # porcelain: Porcelain.spawn(ffmpeg_os_path, hls_cmd, in: :receive, out: :stream),
          %{ffmpeg_pid: ffmpeg_pid}

        args[:type] == "evision" ->
          IO.puts("STARTED EVISION FFMPEG-------")
          %{}

        # %{porcelain: Porcelain.spawn(ffmpeg_os_path, evision_cmd, in: :receive, out: :stream)}

        args[:type] == "dash" ->
          {:ok, ffmpeg_pid} = ExCmd.Process.start_link(dash_cmd) |> dbg()

          # porcelain: Porcelain.spawn(ffmpeg_os_path, dash_cmd, in: :receive, out: :stream)
          %{ffmpeg_pid: ffmpeg_pid}

        args[:type] in ["frame", "echo"] ->
          # porcelain: Porcelain.spawn(ffmpeg_os_path, echo_cmd, in: :receive, out: :stream),
          %{cmd: echo_cmd}
      end
      |> Map.merge(%{type: args[:type], queue: :queue.new()})

    {:ok, state}
  end

  # for test only echo, called by test controller
  def handle_call(:get_data, _from, state) do
    {:reply, state.data, state}
  end

  def handle_call(:pid, _from, state) do
    {:reply, self(), state}
  end

  def handle_call({:enqueue_path, type, path}, _, state) do
    send(self(), {type, path})
    {:reply, :enqueued, state}
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
        #   Porcelain.Process.send_input(state.porcelain, File.read!(path))
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
        data = File.read!(path)
        ExCmd.Process.write(state.ffmpeg_pid, data)
        # Porcelain.Process.send_input(state.porcelain, data)

        send(self(), :process_hls_queue)
        {:noreply, %{state | queue: new_queue}}

      {:empty, _} ->
        IO.puts("Processed------")
        {:noreply, state}
    end
  end

  def handle_info({:stop, type}, state) when type in ["hls", "face"] do
    ExCmd.Process.stop(state.ffmpeg_pid)

    # Porcelain.Process.signal(state.porcelain, :kill)
    # Porcelain.Process.stop(state.porcelain)
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
        Porcelain.Process.send_input(state.porcelain, data)
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
  # def handle_info({"echo", _data, _sender_pid}, state) do
  #   # DO SOMETHING ????
  #   {:noreply, state}
  # end

  # def handle_info({:echo, _data, _sender_pid}, state) do
  #   {:noreply, state}
  # end

  # def handle_info(:evision, state) do
  #   IO.puts("EVISION Process------")
  #   capture = Evision.VideoCapture.videoCapture(0)
  #   frame = Evision.VideoCapture.read(capture) |> dbg()
  #   grey = Evision.cvtColor(frame, Evision.Constant.cv_COLOR_BGR2GRAY())

  #   face_cascade_path =
  #     Path.join(
  #       Application.get_env(:rtc, :models)[:haar_cascade],
  #       "haarcascade_frontalface_default.xml"
  #     )

  #   face_cascade_model = Evision.CascadeClassifier.cascadeClassifier(face_cascade_path)
  #   faces = Evision.CascadeClassifier.detectMultiScale(face_cascade_model, grey)
  #   IO.inspect(faces)
  #   Enum.reduce(faces, frame, fn {x, y, w, h}, mat ->
  #     Cv.rectangle(mat, {x, y}, {x + w, y + h}, {0, 0, 255}, thickness: 2)
  #   end)

  #   {:noreply, state}
  # end
end
