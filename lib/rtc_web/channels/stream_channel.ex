defmodule RtcWeb.StreamChannel do
  use RtcWeb, :channel
  require Logger

  alias Vix.Vips.Operation, as: Vops
  alias Vix.Vips.Image, as: Vimage
  alias Rtc.FFmpegStreamer

  @impl true

  # capture frames from the video
  def join("stream:frame", payload, socket) do
    {:ok, assign(socket, %{type: "frame", user_id: payload["userId"]})}
  end

  def join("stream:" <> type, payload, socket) do
    # start the Streamer/Porcelain process for HLS
    send(self(), {:start_streamer, type})

    {:ok, assign(socket, %{type: type, user_id: payload["userId"]})}
  end

  @impl true
  def handle_info({:start_streamer, type}, socket) do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        Rtc.DynSup,
        {FFmpegStreamer, [type: type, user_id: socket.assigns.user_id]}
      )

    {:noreply, assign(socket, :streamer, pid)}
  end

  @impl true
  def handle_in("data", data, socket) do
    byte_size(data) |> dbg()
    # we take the "data" part of the data URL
    [_signature, b64stream] =
      String.split(data, ",", parts: 2, trim: true)

    # signature in ["data:video/x-matroska;codecs=avc1;base64", "data:video/webm;codecs=vp8;base64"]

    # we decode the base64 data and send it to the streamer (FFMPEG process)
    case Base.decode64(b64stream) do
      {:ok, stream} ->
        send(socket.assigns.streamer, {socket.assigns.type, stream})

      :error ->
        Logger.warning("Error decoding video data")
    end

    {:noreply, socket}
  end

  def handle_in("frame", msg, %{assigns: %{type: "frame"}} = socket) do
    data = Base.decode64!(msg)

    with {:ok, {%Vimage{} = t_img, _}} <-
           Vops.webpload_buffer(data),
         {:ok, _t} <-
           Vix.Vips.Image.write_to_tensor(t_img) do
      # check
      Vops.avg(t_img) |> dbg()
      {:noreply, socket}
    else
      {:error, msg} ->
        IO.puts("Error decoding image #{inspect(msg)}")
        {:noreply, socket}
    end
  end

  # def terminate(reason, arg1) do
  # end
end
