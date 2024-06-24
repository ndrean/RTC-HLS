defmodule RtcWeb.SignalingChannel do
  @moduledoc """
  The Signaling channel server.

  Starts ExWebRTC processes for the room if selected.

  Relays signaling messages between client<->client,  and ExWebRTC server <-> client.
  """

  use RtcWeb, :channel
  require Logger

  ## RoomSocket -> Channel
  @impl true
  def join("room:" <> id = _room_id, payload, socket) do
    send(self(), {:after_join, id})
    {:ok, assign(socket, %{room_id: id, user_id: payload["userId"], module: payload["module"]})}
  end

  #### ExWebRTC channel -> Server
  @impl true
  def handle_info({:after_join, id}, socket) when socket.assigns.module == "echo" do
    # start the ExWebRTC PeerConnection
    :connected =
      Rtc.RoomEcho.connect(room_id: id, channel: self(), user_id: socket.assigns.user_id)

    {:noreply, socket}
  end

  #### ExWebRTC channel -> Server
  def handle_info({:after_join, id}, socket) when socket.assigns.module == "server" do
    :connected =
      Rtc.RoomServer.connect(room_id: id, channel: self(), user_id: socket.assigns.user_id)

    {:noreply, socket}
  end

  #### WebRTC: channel -> client
  def handle_info({:after_join, _id}, socket) when socket.assigns.module == "web" do
    # to signal other connected peers to start the WebRTC PeerConnection
    :ok = broadcast_from(socket, "new", %{"from" => socket.assigns.user_id})

    Logger.debug("--> forward #{socket.assigns.user_id}: NEW \n")
    {:noreply, socket}
  end

  #### ExWebRTC: forwarding ExWebRTC msg -> client
  def handle_info({:signaling, %{"type" => type} = msg}, socket) do
    # use 'push' to send the signaling message to the client on the same socket
    :ok = push(socket, type, msg)
    Logger.debug("--> from Server: forward #{type} \n")

    {:noreply, socket}
  end

  #### WebRTC signaling client -> client
  @impl true
  def handle_in(event, msg, socket) when socket.assigns.module == "web" do
    # use 'broadcast_from' to send the signaling message to all OTHER clients in the room
    :ok = broadcast_from(socket, event, msg)
    Logger.debug("--> broadcast_from #{socket.assigns.user_id}: #{event} \n")

    {:noreply, socket}
  end

  #### ExWebRTC signaling client -> server
  def handle_in(event, msg, socket) when socket.assigns.module in ["server", "echo"] do
    Rtc.RoomEcho.receive_signaling_msg(socket.assigns.room_id, msg)
    Logger.debug("--> to: ExWebRTC_from #{socket.assigns.user_id}: #{event} \n")

    {:noreply, socket}
  end

  @impl true
  def terminate(reason, %{assigns: %{user_id: uid, room_id: rid}} = _socket) do
    :ok = Logger.debug("Channel: stop #{rid}, #{uid},reason: #{inspect(reason)}")
  end
end
