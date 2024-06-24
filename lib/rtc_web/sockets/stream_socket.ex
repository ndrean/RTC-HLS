defmodule RtcWeb.StreamSocket do
  use Phoenix.Socket

  @moduledoc """
  The socket for the HLS channel.

  The server endpoint of this socket is defined in `lib/rtc_web/endpoint.ex`.

  The client endpoint is defined in `assets/js/streamSocket.js`.

  The connection is established in `assets/js/app.js`.
  """

  channel "stream:*", RtcWeb.StreamChannel

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
