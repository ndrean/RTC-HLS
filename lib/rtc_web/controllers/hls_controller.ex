defmodule RtcWeb.HlsController do
  use RtcWeb, :controller

  alias Rtc.FFmpegStreamer

  def files(conn, %{"type" => type, "file" => %Plug.Upload{path: path} = _file}) do
    crypted_user_id =
      fetch_session(conn) |> get_session(:user_id)

    {:ok, user_id} =
      Phoenix.Token.verify(RtcWeb.Endpoint, "user id", crypted_user_id)

    # ffmpepg_pid = FFmpegStreamer.pid(%{type: "hls", user_id: user_id})

    # case Process.alive?(ffmpepg_pid) do
    #   false ->
    #     conn
    #     |> put_status(202)
    #     |> json(%{response: "stopped"})

    #   true ->
    :processed =
      Task.Supervisor.async(Rtc.TaskSup, fn ->
        data =
          File.read!(path)

        FFmpegStreamer.process_hls_chunk(%{type: type, user_id: user_id, chunk: data})
        # Plug.Upload.give_away(file, ffmpeg_pid, self())
        # FFmpegStreamer.process_hls_chunk(%{type: "hls", user_id: user_id, chunk: file})
      end)
      |> Task.await()

    conn
    |> put_status(201)
    |> json(%{response: "ok"})

    # end
  end
end
