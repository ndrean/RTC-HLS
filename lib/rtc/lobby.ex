defmodule Rtc.Lobby do
  @moduledoc false
  use GenServer, restart: :permanent

  require Logger

  alias Rtc.{RoomEcho, RoomServer, DynSup}

  def start_link(_opts), do: GenServer.start_link(__MODULE__, {}, name: __MODULE__)

  def create_room(args), do: GenServer.call(__MODULE__, {:create_room, args})

  @doc """
    Two sessions are running an echo server, and two peers joined room 1.
      iex> Rtc.Lobby.state
      %{
        rooms: MapSet.new([
          {#PID<0.1099.0>, "echo:phx-F9cj9ul_s2v2wgRB", 1},
          {#PID<0.1148.0>, "echo:phx-F9ce_pyAc6HkbQeB", 1},
          {#PID<0.1208.0>, "1", 2}
        ])
      }
  """
  def state(), do: GenServer.call(__MODULE__, :state)

  @doc """

      iex> Rtc.Lobby.pids
      [
        {#PID<0.1099.0>,Rtc.RoomEcho},
        {#PID<0.1148.0>, Rtc.RoomEcho},
        {#PID<0.1208.0>, Rtc.RoomServer}
      ]
  """
  def pids,
    do:
      DynamicSupervisor.which_children(DynSup)
      |> Enum.map(fn {_, pid, _, [name]} -> {pid, name} end)

  ##########################################################
  @impl true
  def init(_), do: {:ok, %{rooms: MapSet.new()}}

  @impl true
  def handle_call(:state, _, state), do: {:reply, state, state}

  @impl true
  def handle_call({:create_room, args}, _, state) do
    lv_pid = Keyword.get(args, :lv_pid)
    type = Keyword.get(args, :type)
    room_id = Keyword.get(args, :room_id)

    state = Map.merge(state, %{lv_pid: lv_pid})

    module =
      case type do
        :echo -> RoomEcho
        :server -> RoomServer
      end

    # we add a 0 or 1 if the room starts or is already started
    {pid, i} =
      case DynamicSupervisor.start_child(
             DynSup,
             {module, args}
           ) do
        {:ok, pid} ->
          Process.monitor(pid)
          Logger.info("Lobby starts Room:#{room_id}")
          {pid, 0}

        {:error, {:already_started, pid}} ->
          Logger.debug("Lobby already started Room:#{room_id}")
          {pid, 1}
      end

    # we add the nb of users per room
    case MapSet.to_list(state.rooms) |> Enum.find(fn {p, _, _} -> p === pid end) do
      nil ->
        rooms = MapSet.put(state.rooms, {pid, room_id, 1})
        {:reply, :created, %{state | rooms: rooms}}

      {^pid, ^room_id, n} ->
        rooms = MapSet.delete(state.rooms, {pid, room_id, n})
        rooms = MapSet.put(rooms, {pid, room_id, n + i})
        {:reply, :created, %{state | rooms: rooms}}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    MapSet.to_list(state.rooms)
    |> Enum.find(fn {p, _, _} -> p === pid end)
    |> case do
      nil ->
        {:noreply, state}

      {^pid, room, n} ->
        rooms = MapSet.delete(state.rooms, {pid, room, n})
        Logger.warning("--> Lobby: Room #{room} is DOWN, #{inspect(reason)}")

        {:noreply, %{state | rooms: rooms}}
    end
  end

  @impl true
  def terminate(reason, state) do
    Logger.warning("Lobby stopped, reason: #{inspect(reason)}")
    {:stop, reason, state}
  end
end
