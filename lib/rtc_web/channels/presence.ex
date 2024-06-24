defmodule RtcWeb.Presence do
  @moduledoc """
  Provides presence tracking to channels and processes.

  See the [`Phoenix.Presence`](https://hexdocs.pm/phoenix/Phoenix.Presence.html)
  docs for more details.
  """
  use Phoenix.Presence,
    otp_app: :rtc,
    pubsub_server: Rtc.PubSub

  require Logger

  def track_user(key, params) do
    Logger.info("Track #{key} with params #{inspect(params)}")
    track(self(), "proxy:users", key, params)
  end

  @doc """

  The Presence process keeps the list of tracked users with their meta-data.

  You can list all the user with this function.

    ## Example
      iex> RtcWeb.Presence.list_users()
        [
          %{
            id: "576460752303420765",
            metas: [%{id: "lobby", phx_ref: "F9N9z3W27J7VhwTi"}]
          },
          %{
            id: "576460752303421309",
            metas: [%{id: "1", phx_ref: "F9N9zS07nEzVhwXm"}]
          }
        ]
  """
  def list_users do
    RtcWeb.Presence.list("proxy:users")
    |> Enum.map(fn {_, presence} -> presence end)
  end

  @doc """
  Helper function to get the list of users in a room

    ## Example
      iex> RtcWeb.Presence.users_room()
      [{"576460752303423452", "lobby"},{"576460752303422911", "1"}]
  """
  def users_room() do
    for {uid, %{metas: [%{room_id: room_id}]}} <- list("proxy:users"), do: {uid, room_id}
  end

  @doc """
  List of users in a room

    ## Example
      iex> RtcWeb.Presence.users_in_room("1")
      ["576460752303422911"]
  """

  def users_in_room(rid) do
    users_room()
    |> Enum.filter(fn {_, room_id} -> room_id === rid end)
    |> Enum.map(fn {uid, _} -> uid end)
  end

  @doc """
  Check if the user is in the room

    ## Example
      iex> RtcWeb.Presence.in_room?("576460752303422911", "1")
      true
  """
  def in_room?(uid, rid) do
    users_room()
    |> Enum.member?({uid, rid})
  end

  @doc """
  Check if the room already contains 2 participants, in which case is considered as full
  """
  def full?(rid, n) when is_binary(rid) do
    {rid, users_in_room(rid) |> length() |> Kernel.>(n)}
  end

  # We overwrite the callback.
  # You have to return the metas and have to add the mandatory "id" key.
  # Since the tracking_key is the user_id, we return assign the tracking_key to the id.
  @impl true
  def fetch(_topic, presences) do
    for {tracking_key, %{metas: metas}} <- presences, into: %{} do
      {tracking_key, %{metas: metas, id: tracking_key}}
    end
  end

  # Callbacks --------------------------------------------------------
  @impl true
  def init(_opts) do
    Logger.debug("Presence process: #{inspect(self())}")
    {:ok, %{pid: self()}}
  end

  @impl true
  def handle_metas(topic, %{leaves: leaves, joins: joins}, _presences, state) do
    for {_user_id, presence} <- joins do
      :ok =
        Phoenix.PubSub.local_broadcast(
          Rtc.PubSub,
          topic,
          {:join, presence}
        )
    end

    for {_user_id, presence} <- leaves do
      :ok =
        Phoenix.PubSub.local_broadcast(
          Rtc.PubSub,
          topic,
          {:leave, presence}
        )

      {:ok, state}
    end

    {:ok, state}
  end
end
