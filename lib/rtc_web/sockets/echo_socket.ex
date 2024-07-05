# defmodule RtcWeb.EchoSocketSerializer do
#   @behaviour Phoenix.Socket.Serializer

#   def decode!(iodata, _) do
#     %Phoenix.Socket.Message{payload: iodata}
#   end

#   def encode!(%Phoenix.Socket.Message{payload: data}) do
#     {:socket_push, :binary, data}
#   end
#   def encode!(%Phoenix.Socket.Reply{payload: data}) do
#     {:socket_push, :binary, data}
#   end

#   def fastlane!(%Phoenix.Socket.Broadcast{payload: _payload}= msg) do
#     {:socket_push, :binary, msg}
#   end
# end

defmodule RtcWeb.EchoSocket do
  @behaviour Phoenix.Socket.Transport
  alias ExCmd.Process, as: Proc

  def child_spec(_opts) do
    :ignore
  end

  def connect(state) do
    %{params: params} = state

    case Phoenix.Token.verify(RtcWeb.Endpoint, "user token", params["user_token"]) do
      {:ok, uid} ->
        # {:ok, proc} =
        #   # ExCmd.Process.start_link(~w(ffmpeg -i pipe:0  -pixel_format uyvy422 demo/test_%004d.jpg),
        #   #   log: true
        #   # )
        #   ExCmd.Process.start_link(~w(ffmpeg -i pipe:0  -pixel_format uyvy422 -f rawvideo -pix_fmt yuv420p pipe:1),
        #     log: true
        #   )
        cmd_file =
          ~w(ffmpeg -loglevel debug -i pipe:0 -r 15 -video_size 640x480 demo/pics/fr_%0004d.jpg)

        _cmd_buff =
          ~w(ffmpeg -loglevel debug -i pipe:0 -r 15 -video_size 640x480 -f rawvideo pipe:1)

        {:ok, proc_file} = Proc.start_link(cmd_file, log: true)
        # {:ok, proc_buff} = Proc.start_link(cmd_buff, log: true)

        face_cascade_model = Evision.CascadeClassifier.cascadeClassifier(Rtc.Env.haar())

        state =
          state
          |> Map.merge(%{
            user_id: uid,
            model: face_cascade_model,
            # proc_buff: proc_buff,
            proc_file: proc_file,
            cmd_file: cmd_file
          })

        {:ok, state}

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end

  def init(state) do
    {:ok, state}
  end

  def handle_in({heartbeat, [opcode: :text]}, state) do
    {:reply, :ok, {:text, heartbeat}, state}
  end

  def handle_in({msg, [opcode: :binary]}, state) do
    dbg(byte_size(msg))

    :ok = Proc.write(state.proc_file, msg)

    ExCmd.stream!(state.cmd, input: msg, log: true) |> Stream.run()

    # res = ExCmd.stream!(~w(ffmpeg -loglevel debug -i pipe:0  -pixel_format uyvy422 -video_size 640x480 -f rawvideo -pix_fmt yuv420p pipe:1), input: msg, log: true)
    # |> Stream.into(IO.read(:all) |> dbg())
    # |> Evision.Mat.from_binary(:u8, 640, 480,3 )
    # |> dbg()
    # |> Evision.cvtColor(Evision.Constant.cv_COLOR_BGR2GRAY())
    # |> then(&Evision.CascadeClassifier.detectMultiScale(model, &1, scaleFactor: 1.8, minNeighbors: 1))
    # |>dbg()

    # {:reply, :ok, {:binary, msg}, state}
    {:ok, state}
  end

  def handle_info(_, state) do
    {:ok, state}
  end

  def terminate(_, _) do
    :ok
  end
end
