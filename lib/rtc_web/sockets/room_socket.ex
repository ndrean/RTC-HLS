defmodule RtcWeb.RoomSocket do
  use Phoenix.Socket

  @moduledoc """
  The socket for the Room channel.

  The server endpoint of this socket is defined in `lib/rtc_web/endpoint.ex`.

  The client endpoint is defined in `assets/js/roomSocket.js`.

  The connection is established in `assets/js/app.js`.
  """

  channel "room:*", RtcWeb.SignalingChannel

  require Logger

  @impl true
  def connect(%{"user_token" => user_token}, socket, _connect_info) do
    case Phoenix.Token.verify(RtcWeb.Endpoint, "user token", user_token) do
      {:ok, uid} ->
        {:ok, assign(socket, :user_id, uid)}

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end

  # to test!!
  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"
end
