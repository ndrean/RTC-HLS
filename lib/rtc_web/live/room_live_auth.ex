defmodule RtcWeb.RoomLiveAuth do
  @moduledoc """
  Mock authentication for the rooms using Phoenix.Token.verify/3
  """

  use RtcWeb, :live_view
  require Logger

  def on_mount(:rooms, %{}, session, socket) do
    case Phoenix.Token.verify(RtcWeb.Endpoint, "user id", session["user_id"]) do
      {:ok, user_id} ->
        Logger.info("User is authenticated #{user_id}")
        {:cont, assign(socket, :user_id, user_id)}

      {:error, _} ->
        Logger.info("User is not authenticated")
        {:halt, redirect(socket, to: "/")}
    end
  end
end
