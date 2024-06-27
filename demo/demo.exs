Application.put_env(:sample, Example.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 5001],
  server: true,
  live_view: [signing_salt: "aaaaaaaa"],
  secret_key_base: String.duplicate("a", 64)
)

Mix.install([
  {:plug_cowboy, "~> 2.7"},
  {:jason, "~> 1.4"},
  {:phoenix, "~> 1.7"},
  {:phoenix_live_view, "~> 0.20"},
  {:ex_cmd, "~> 0.12"},
])

defmodule Example.ErrorView do
  def render(template, _), do: Phoenix.Controller.status_message_from_template(template)
end

defmodule Example.HomeLive do
  use Phoenix.LiveView, layout: {__MODULE__, :live}

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :count, 0)}
  end

  defp phx_vsn, do: Application.spec(:phoenix, :vsn)
  defp lv_vsn, do: Application.spec(:phoenix_live_view, :vsn)

  def render("live.html", assigns) do
    ~H"""
    <script src={"https://cdn.jsdelivr.net/npm/phoenix@#{phx_vsn()}/priv/static/phoenix.min.js"}>
    </script>
    <script
      src={"https://cdn.jsdelivr.net/npm/phoenix_live_view@#{lv_vsn()}/priv/static/phoenix_live_view.min.js"}
    >
    </script>
    <script>
      let liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket)
      liveSocket.connect()

      function run() {

          navigator.mediaDevices.getUserMedia({video: true})
          .then((stream)=> {
            //let video = document.getElementById("hls");
            let send = true;
            document.getElementById("stop").onclick = () => {
                send = false;
            }


            video.srcObject = stream
            let mediaRecorder = new MediaRecorder(stream);
            mediaRecorder.ondataavailable = ({data}) => {
              if (!send) return;
              if (data.size > 0) {
                console.log(data.size)
                const file = new File([data], "chunk.webm", {
                  type: "video/webm",
                });
              const formData = new FormData();
              formData.append("file", file);
              fetch(`/upload`, {method: "POST",body: formData})
              .then((res) => res.text())
              .then(console.log)
              }
            }
            mediaRecorder.start(1000)
            })
          }
          run()



    </script>

    <%= @inner_content %>
    """
  end

  def render(assigns) do
    ~H"""
    <video id="video" width="300" height="300" controls autoplay></video>
    <button type="button" id="stop" phx-click="stop">STOP</button>
    """
  end

  def handle_event("stop", _, socket) do
    FFmpeger.stop()
    {:noreply, socket}
  end
end

defmodule Example.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug Plug.Parsers, parsers: [:urlencoded, :multipart]
  end

  scope "/", Example do
    pipe_through(:browser)

    live("/", HomeLive, :index)
    post("/upload", Post, :upload)
  end
end

defmodule FFmpeger do
  use GenServer

  def start_link(_), do:
    GenServer.start_link(__MODULE__, {}, name: __MODULE__)


  def enqueue(path), do:
    GenServer.call(__MODULE__, {:process, path})

  def stop(), do: GenServer.call(__MODULE__, :stop)


  def init(_) do
    dir = System.tmp_dir()
    playlist_path = Path.join(dir, "stream.m3u8")
    segment_path = Path.join(dir, "segment_%03d.ts")
    ffmpeg = System.find_executable("ffmpeg")
    cmd = ~w(#{ffmpeg} -loglevel debug -hide_banner -i pipe:0 -r 20 -c:v libx264 -hls_time 2 -hls_list_size 5 -hls_flags delete_segments+append_list -hls_playlist_type event  -hls_segment_filename #{segment_path} #{playlist_path})

    {:ok, _pid} = ExCmd.Process.start_link(cmd, log: true)
  end

  def handle_call({:process, path}, _from, pid) do
    data = File.read!(path)
    ExCmd.Process.write(pid, data)
    IO.puts "processed-----------------#{byte_size(data)}"
    {:reply, :processed, pid}
  end

  def handle_call(:stop, _from, pid) do
    IO.puts "stopping-----------------"
    :ok  =ExCmd.Process.close_stdin(pid)
    :eof = ExCmd.Process.read(pid)
    {:ok, 0} = ExCmd.Process.await_exit(pid)
    {:stop, :shutdown, pid}
  end
end

defmodule Example.Post do
  use Phoenix.Controller

  def upload(conn,%{"file" => %Plug.Upload{path: path}} ) do
    :processed = FFmpeger.enqueue(path)

    conn |> put_status(201) |> json(%{status: "ok"})
  end
end

defmodule Example.Endpoint do
  use Phoenix.Endpoint, otp_app: :sample
  socket("/live", Phoenix.LiveView.Socket)
  plug(Example.Router)
end

{:ok, _} = Supervisor.start_link([Example.Endpoint, FFmpeger], strategy: :one_for_one)
Process.sleep(:infinity)
