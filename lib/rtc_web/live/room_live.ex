defmodule RtcWeb.RoomLive do
  @moduledoc """
  LiveView for the rooms
  """
  use RtcWeb, :live_view

  require Logger

  alias Rtc.Lobby
  alias Rtc.FFmpegStreamer
  alias RtcWeb.Presence
  alias RtcWeb.{Header, Videos, Navigate, UsersInRoom, Videos, RoomForm}

  on_mount {RtcWeb.RoomLiveAuth, :rooms}

  defp subscribe(topic) do
    :ok = Phoenix.PubSub.subscribe(Rtc.PubSub, topic)
  end

  defp get_pid(ref) do
    case ref do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
    end
  end

  @impl true
  def mount(params, _session, socket) do
    # "params" comes from the URL/navigation, "session" from Plug

    room_id = Map.get(params, "room_id", "lobby")
    user_id = socket.assigns.user_id

    socket =
      socket
      |> stream(:presences, Presence.list_users())
      |> assign(%{
        form: to_form(params),
        id: socket.id,
        room_id: room_id,
        user_id: user_id,
        room: room_id,
        room_numbers: ["1", "2", "3"],
        tab: nil,
        playlist_ready: false,
        active: nil,
        hls_streamer_pid: nil,
        face_streamer_pid: nil,
        frame_streamer_pid: nil,
        evision_streamer_pid: nil
      })

    if connected?(socket) do
      Logger.info("LV connected --------#{socket.id}")
      subscribe("proxy:users")
      subscribe("hls:m3u8")
      Presence.track_user(user_id, %{room_id: room_id})
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"ex_room_id" => rid}, _uri, socket) do
    IO.puts("PARAMS ROOM---------------")

    :created =
      Lobby.create_room(
        room_id: rid,
        type: :server,
        lv_pid: self(),
        user_id: socket.assigns.user_id
      )

    {:noreply, assign(socket, :live_action, :room)}
  end

  def handle_params(%{"echo" => echo}, _uri, socket) do
    IO.puts("PARAMS ECHO-----------------")

    :created =
      Lobby.create_room(
        room_id: echo,
        type: :echo,
        lv_pid: self(),
        user_id: socket.assigns.user_id
      )

    {:noreply, assign(socket, :live_action, :echo)}
  end

  def handle_params(_p, _uri, socket) do
    {:noreply, socket}
  end

  # Callbacks from client -----------------------------

  @impl true
  # event from Room selection to navigate to
  def handle_event("goto", %{"ex_room_id" => rid}, socket) do
    # limit rooms to 2 users: using ExRTC
    exroom = "ex_#{rid}"

    case Presence.full?(exroom, 1) do
      {^exroom, true} ->
        {:noreply, put_flash(socket, :error, "Room is full")}

      {^exroom, false} ->
        {:noreply,
         socket
         |> assign(:room_id, exroom)
         |> push_navigate(to: ~p"/ex/#{exroom}")}
    end
  end

  def handle_event("goto", %{"web_room_id" => rid}, socket) do
    # limit rooms to 3 users: using WebRTC
    wroom = "web_#{rid}"

    case Presence.full?(wroom, 2) do
      {^wroom, true} ->
        {:noreply, put_flash(socket, :error, "Room is full")}

      {^wroom, false} ->
        {:noreply,
         socket
         |> assign(:room_id, wroom)
         |> push_navigate(to: ~p"/web/#{wroom}")
         |> push_event("js-exec", %{to: "#spinner", attr: "data-plz-wait"})}
    end
  end

  # event: JS.push "switch" in "tab_selector"
  # maybe starts FFmpeg streamer and sets the tab to navigate to

  def handle_event("switch", %{"tab" => "live"}, socket) do
    # can't go there is no playlist available
    ready =
      Application.fetch_env!(:rtc, :hls)[:hls_dir]
      |> File.ls!()
      |> Enum.member?("stream.m3u8")

    IO.puts("first check for HLS....#{ready}")

    if ready do
      {:noreply, socket |> assign(:tab, "live") |> push_patch(to: ~p"/live_stream")}
    else
      {:noreply, put_flash(socket, :info, "No stream available yet")}
    end
  end

  def handle_event("switch", %{"tab" => "hls"}, socket) do
    hls_streamer_pid =
      DynamicSupervisor.start_child(
        Rtc.DynSup,
        {FFmpegStreamer, [type: "hls", user_id: socket.assigns.user_id]}
      )

    hls_streamer_pid = get_pid(hls_streamer_pid)

    {:noreply, assign(socket, tab: "hls", hls_streamer_pid: hls_streamer_pid)}
  end

  def handle_event("switch", %{"tab" => "face"}, socket) do
    face_streamer_pid =
      DynamicSupervisor.start_child(
        Rtc.DynSup,
        {FFmpegStreamer, [type: "face", user_id: socket.assigns.user_id]}
      )

    face_streamer_pid = get_pid(face_streamer_pid)

    {:noreply, assign(socket, tab: "face", face_streamer_pid: face_streamer_pid)}
  end

  def handle_event("switch", %{"tab" => "evision"}, socket) do
    evision_streamer_pid =
      DynamicSupervisor.start_child(
        Rtc.DynSup,
        {Rtc.ProcessorAgent, [type: "evision", user_id: socket.assigns.user_id]}
      )

    evision_streamer_pid = get_pid(evision_streamer_pid)

    evision_streamer_pid |> dbg()

    {:noreply, assign(socket, tab: "evision", evision_streamer_pid: evision_streamer_pid)}
  end

  def handle_event("switch", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :tab, tab)}
  end

  def handle_event("stop-hls-event", _, %{assigns: %{tab: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("stop-hls-stream", %{"tab" => "hls"}, socket) do
    %{assigns: %{tab: tab, hls_streamer_pid: hls_streamer_pid}} = socket

    case hls_streamer_pid do
      nil ->
        {:noreply, socket}

      pid ->
        IO.puts("Stopping-------")
        send(pid, {:stop, tab})

        {:noreply, push_event(socket, "stop", %{}) |> assign(:hls_streamer_pid, nil)}
    end
  end

  def handle_event("stop-hls-stream", %{"tab" => "face"}, socket) do
    %{assigns: %{tab: tab, face_streamer_pid: face_streamer_pid}} = socket

    case face_streamer_pid do
      nil ->
        {:noreply, socket}

      pid ->
        IO.puts("Stopping-------")
        send(pid, {:stop, tab})

        {:noreply, push_event(socket, "stop", %{}) |> assign(:face_streamer_pid, nil)}
    end
  end

  def handle_event("stop-dash-stream", _, socket) do
    %{assigns: %{tab: tab, user_id: user_id}} = socket

    # FFmpegStreamer.pid(tab <> "-" <> to_string(user_id))
    FFmpegStreamer.pid(%{type: tab, user_id: user_id})
    |> send({:stop, socket.assigns.tab})

    {:noreply, push_event(socket, "stop", %{}) |> push_patch(to: ~p"/")}
  end

  def handle_event("start-evision", _, %{assigns: %{evision_streamer_pid: pid}} = socket)
      when not is_nil(pid) do
    Rtc.Processor.process_video()
    {:noreply, socket}
  end

  # callbacks from the process -------------------------
  @impl true
  # fliewatcher messages -------------------------------
  def handle_info(:playlist_ready, %{assigns: %{playlist_ready: true}} = socket) do
    # other messages from FileWatcher
    {:noreply, socket}
  end

  def handle_info(:playlist_ready, %{assigns: %{playlist_ready: false}} = socket) do
    # first  message from FileWatcher
    {:noreply, assign(socket, :playlist_ready, true) |> put_flash(:info, "HLS stream is ready")}
  end

  # presence messages -------------------------------
  def handle_info(%{topic: "proxy:users", event: "presence_diff"}, socket) do
    # mandatory callback from Presence "handle_metas"
    {:noreply, socket}
  end

  def handle_info({:join, user_data}, socket) do
    # callback to PubSub broadcast from Presence client
    {:noreply, stream_insert(socket, :presences, user_data)}
  end

  def handle_info({:leave, user_data}, %{assigns: assigns} = socket) do
    # message from Presence
    %{id: uid, metas: [%{room_id: rid}]} = user_data

    case {assigns.room_id != "lobby", rid == assigns.room_id,
          Presence.in_room?(assigns.user_id, rid)} do
      {true, true, true} ->
        # if a user leaves my room which is not the lobby, I want a flash
        {
          :noreply,
          stream_delete(socket, :presences, user_data)
          |> put_flash(:error, "User left #{uid} the room. Room is closed")
        }

      _ ->
        {:noreply, stream_delete(socket, :presences, user_data)}
    end
  end

  # ExRTC messages -------------------------------
  def handle_info(:user_connected, socket) do
    # message from ExRTC when user connected
    {
      :noreply,
      put_flash(socket, :info, "User connected")
      |> push_event("js-exec", %{to: "#spinner", attr: "data-ok-done"})
    }
  end

  # Rendering --------------------------------------------------------
  @impl true
  def render(assigns) when assigns.live_action == :lobby do
    ~H"""
    <section id="lobby">
      <h1 class="text-2xl mb-4">Welcome to the Lobby</h1>
      <p>Liveview socket id: <%= assigns.id %>, <%= inspect(self()) %></p>
      <p>User id: <%= @user_id %></p>
      <br />

      <Navigate.tab_selector
        active_tab={@tab}
        list={[
          %{tab_id: "#frame-js", live_action: "frame", title: "Frame (JS)"},
          %{tab_id: "#echo", live_action: "echo", title: "Echo (Ex)RTC"},
          %{tab_id: "#evision", live_action: "evision", title: "Echo (Evision)"},
          %{tab_id: "#ex_form", live_action: "exrtc", title: "Visio-2 (Ex)RTC"},
          %{tab_id: "#web_form", live_action: "webrtc", title: "Visio-3 (Web)RTC"},
          %{tab_id: "#face-api", live_action: "face", title: "Face API"},
          %{tab_id: "#hls", live_action: "hls", title: "HLS Producer"},
          %{tab_id: "#live-hls", live_action: "live", title: "HLS Viewer"}
        ]}
      />
      <div class="mt-4 mb-4">
        <Navigate.display_tab
          :if={@tab == "face"}
          action={JS.patch("/face")}
          link_text="Face Api in the browser"
          inner_text="We display 2 videos, one with your feed, and another one with the found face contours. The transformed video is HTTP-Live-Streamed from the server."
        />
        <Navigate.display_tab
          :if={@tab == "hls"}
          action={JS.patch("/hls_stream")}
          link_text="HLS Record Stream"
          inner_text="You broadcast a HLS stream from your webcam."
        />
        <Navigate.display_tab
          :if={@tab == "live"}
          action={JS.patch("/live_stream")}
          link_text="HLS Live View"
          inner_text="TODO"
        />

        <Navigate.display_tab
          :if={@tab == "frame"}
          action={JS.patch("/frame")}
          link_text="Play your webcam"
          inner_text="10 frame/s are captured from the webcam and pushed to the server. We run a face recognition and make the streams available for HTTP Live Streaming."
        />
        <Navigate.display_tab
          :if={@tab == "echo"}
          action={JS.navigate("/echo/echo_#{@id}")}
          link_text="Echo Server"
          inner_text="Broadcast yourself via ExRTC. The feed of your webcam is sent via RTC to the Elixir-RTC. The server broadcasts back streams in the other <video> element."
        />
        <Navigate.display_tab
          :if={@tab == "evision"}
          action={JS.patch("/evision/evision_#{@id}")}
          link_text="Echo Evision"
          inner_text="Capture your webcam and run a face recognition. The feed of your webcam is sent via HTTP to the Phoenix server. The server broadcasts back streams in the other <video> element."
        />

        <RoomForm.select
          :if={@tab == "exrtc"}
          id="ex_form"
          form={@form}
          field={:ex_room_id}
          options={@room_numbers}
          title="Connect 2 users in a room via an Elixir RTC server."
        />
        <RoomForm.select
          :if={@tab == "webrtc"}
          id="web_form"
          form={@form}
          field={:web_room_id}
          options={@room_numbers}
          title="Connect up to 3 users in a room via WEB-RTC."
        />
      </div>

      <hr />
      <UsersInRoom.list streams={@streams} room={@room} room_id={@room_id} />
    </section>
    """
  end

  def render(assigns) when assigns.live_action == :echo do
    ~H"""
    <section id="room-view" data-user-id={@user_id} data-module="echo" phx-hook="rtc">
      <Header.display
        header="ExWebRTC Echo server"
        id={@id}
        pid={inspect(self())}
        user_id={@user_id}
        room_id={@room_id}
      />
      <Navigate.home />
      <Videos.play />
      <canvas id="canvas"></canvas>
    </section>
    """
  end

  def render(assigns) when assigns.live_action == :evision do
    ~H"""
    <section id="echo-view" data-user-id={@user_id} data-module="evision" phx-hook="echo_evision">
      <Header.display
        header="Echo Evision from server"
        id={@id}
        pid={inspect(self())}
        user_id={@user_id}
        room_id={@room_id}
      />
      <Navigate.home />
      <Videos.play />
      <canvas id="canvas"></canvas>
    </section>
    """
  end

  def render(assigns) when assigns.live_action == :room do
    ~H"""
    <section id="room-view" data-user-id={@user_id} data-module="server" phx-hook="rtc">
      <Header.display
        header="ExWebRTC Server"
        id={@id}
        pid={inspect(self())}
        user_id={@user_id}
        room_id={@room_id}
      />
      <Navigate.home />
      <Videos.play />
      <UsersInRoom.list streams={@streams} room={@room} room_id={@room_id} />
    </section>
    """
  end

  def render(assigns) when assigns.live_action == :web do
    ~H"""
    <section id="room-view" data-user-id={@user_id} data-module="web" phx-hook="web">
      <Header.display
        header="WebRTC multi-peers"
        id={@id}
        pid={inspect(self())}
        user_id={@user_id}
        room_id={@room_id}
      />
      <Navigate.home />
      <Videos.grid />
      <UsersInRoom.list streams={@streams} room={@room} room_id={@room_id} />
    </section>
    """
  end

  def render(assigns) when assigns.live_action == :frame do
    ~H"""
    <section id="frame-js" data-user-id={@user_id} phx-hook="frame">
      <Header.display
        header="Frame drawing with JS"
        id={@id}
        pid={inspect(self())}
        user_id={@user_id}
        room_id={@room_id}
      />
      <Navigate.home spinner={false} />
      <Videos.frame />
      <UsersInRoom.list streams={@streams} room={@room} room_id={@room_id} />
    </section>
    """
  end

  def render(assigns) when assigns.live_action == :face do
    ~H"""
    <section id="face" class="mx-auto p-4" phx-update="ignore" phx-hook="faceApi">
      <Header.display
        header="Play with face-api.js"
        id={@id}
        pid={inspect(self())}
        user_id={@user_id}
        room_id={@room_id}
      />
      <%!-- error with requestAnimation in Chrome: never cleared => reload --%>
      <Navigate.home spinner={false} />
      <.button phx-click="stop-hls-stream" phx-value-tab="face">Stop streaming</.button>
      <br />
      <Videos.face />
      <UsersInRoom.list streams={@streams} room={@room} room_id={@room_id} />
    </section>
    """
  end

  def render(assigns) when assigns.live_action == :hls do
    ~H"""
    <section id="hls" data-user-id={@user_id} phx-hook="InputHls">
      <Header.display
        header="Live Streaming with HLS"
        id={@id}
        pid={inspect(self())}
        user_id={@user_id}
        room_id={@room_id}
      />
      <Navigate.home />
      <br />
      <hr />
      <.button phx-click="stop-hls-stream" phx-value-tab="hls">Stop streaming</.button>
      <br />
      <video
        id="hls-in-video"
        width="640"
        height="480"
        class="w-full h-auto object-cover rounded-lg max-h-60"
        controls
        autoplay
      >
      </video>
    </section>
    """
  end

  def render(assigns) when assigns.live_action == :live do
    ~H"""
    <div class="flex flex-col items-center space-y-4 mb-4">
      <.link navigate={~p"/"} class="border-solid rounded">
        <.icon name="hero-home" class="h-8 w-8 mr-4" />
        <span class="text-2xl">Back to the Lobby</span>
      </.link>
    </div>
    <button
      type="button"
      class="ext-white bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:ring-blue-300 font-medium rounded-lg text-sm px-5 py-2.5 me-2 mb-2 dark:bg-blue-600 dark:hover:bg-blue-700 focus:outline-none dark:focus:ring-blue-800"
      id="play-hls"
    >
      Play
    </button>
    <video
      id="hls-out-video"
      width="640"
      height="480"
      class="w-full h-auto object-cover rounded-lg max-h-60"
      controls
      autoplay
      phx-hook="LiveHls"
    >
    </video>
    <br />
    <hr />
    <br />

    <button
      type="button"
      class="ext-white bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:ring-blue-300 font-medium rounded-lg text-sm px-5 py-2.5 me-2 mb-2 dark:bg-blue-600 dark:hover:bg-blue-700 focus:outline-none dark:focus:ring-blue-800"
      id="play-dash"
    >
      Play
    </button>
    <video
      id="dash-out-video"
      width="640"
      height="480"
      class="w-full h-auto object-cover rounded-lg max-h-60"
      controls
      autoplay
      data-manifest-url="/dash/stream.mpd"
    >
    </video>
    """
  end
end
