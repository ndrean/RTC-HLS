defmodule RtcWeb.HlsController do
  use RtcWeb, :controller

  alias Rtc.FFmpegStreamer

  def files(conn, %{"type" => type, "file" => %Plug.Upload{path: path}}) do
    :enqueued =
      Task.Supervisor.async_nolink(Rtc.TaskSup, fn ->
        crypted_user_id =
          fetch_session(conn) |> get_session(:user_id)

        {:ok, user_id} =
          Phoenix.Token.verify(RtcWeb.Endpoint, "user id", crypted_user_id)

        FFmpegStreamer.enqueue_path(%{type: type, user_id: user_id, path: path})
      end)
      |> Task.await()

    conn
    |> put_status(201)
    |> json(%{response: "ok"})
  end

  def segment(conn, %{"file" => file}) do
    path = Path.join(Application.fetch_env!(:rtc, :hls)[:hls_dir], file)
    send_file(conn, 200, path)
  end
end
