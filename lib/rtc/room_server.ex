defmodule Rtc.RoomServer do
  use GenServer, restart: :temporary

  @moduledoc """
  The Room module is responsible for managing the WebRTC connection between two peers.

  It is dynamically supervised by the DynSup.

  The Lobby GenServer starts a Room GenServer per room.
  """

  require Logger

  alias ExWebRTC.{ICECandidate, PeerConnection, SessionDescription, MediaStreamTrack}

  @ice_servers [
    %{urls: "stun:stun.l.google.com:19302"},
    %{urls: "stun:stun.l.google.com:5349"}
  ]

  defp id(room_id), do: {:via, Registry, {Rtc.Reg, room_id}}

  def start_link(args) do
    rid = Keyword.get(args, :room_id)
    GenServer.start_link(__MODULE__, args, name: id(rid))
  end

  def connect(room_id: room_id, channel: channel, user_id: user_id),
    do: GenServer.call(id(room_id), {:connect, channel, user_id})

  def receive_signaling_msg(room_id, msg) do
    GenServer.cast(id(room_id), {:receive_signaling_msg, msg})
  end

  # ---- debug helpers
  def running?(room_id), do: GenServer.whereis(id(room_id)) != nil

  @doc """
  The state is build like this:

      iex> Rtc.RoomServer.state("1")
          %{
            :all_connected => true,
            :curr => %{
              pc: #PID<0.1435.0>,
              channel: #PID<0.1434.0>,
              room_id: "ex_1",
              lv_pid: #PID<0.1369.0>
            },
            #PID<0.1382.0> => %{
              pc: #PID<0.1382.0>,
              user_id: "576460752303423483",
              client_v_track_id: 67099719350719025363741411447,
              serv_v_track_id: 69064416796533885559533156454,
              client_a_track_id: 46775190350999117625461897608,
              serv_a_track_id: 30546379485825627782735580608
            },
            ...
            }
          }
  """
  def state(room_id), do: GenServer.call(id(room_id), :state)

  # ---- GenServer callbacks

  @impl true
  def init(args) do
    {:ok,
     %{
       all_connected: false,
       curr: %{
         pc: nil,
         channel: nil,
         room_id: Keyword.get(args, :room_id),
         lv_pid: Keyword.get(args, :lv_pid)
       }
     }}
  end

  @impl true
  def handle_call({:connect, channel_pid, user_id}, _from, state) do
    lv_pid = Rtc.Lobby.state().lv_pid

    Process.monitor(channel_pid)
    {:ok, pc} = PeerConnection.start_link(ice_servers: @ice_servers)

    server_transceivers = setup_transceivers(pc)

    state =
      %{state | curr: Map.merge(state.curr, %{pc: pc, channel: channel_pid, lv_pid: lv_pid})}
      |> Map.put(
        pc,
        Map.merge(%{pc: pc, user_id: user_id}, server_transceivers)
      )

    Logger.info(
      "--> RoomServer #{state.curr.room_id} starts PC #{inspect(pc)}, channel #{inspect(state.curr.channel)}"
    )

    {:reply, :connected, state}
  end

  def handle_call(:state, _from, state), do: {:reply, state, state}

  # ---- receive SDP from client
  @impl true
  def handle_cast(
        {:receive_signaling_msg, %{"type" => "offer"} = msg},
        %{curr: %{pc: pc, channel: channel}} = state
      ) do
    with desc <-
           SessionDescription.from_json(msg["sdp"]),
         :ok <-
           PeerConnection.set_remote_description(pc, desc),
         {:ok, answer} <-
           PeerConnection.create_answer(pc),
         :ok <-
           PeerConnection.set_local_description(pc, answer),
         :ok <-
           gather_candidates(pc) do
      Logger.debug("--> Server sends Answer to remote")

      #  the 'answer' is formatted as a struct, which can't be read by the JS client
      sent_answer = %{
        "type" => "answer",
        "sdp" => %{type: answer.type, sdp: answer.sdp},
        "from" => msg["from"]
      }

      send(channel, {:signaling, sent_answer})
      {:noreply, state}
    else
      error ->
        Logger.error("Server: error creating answer: #{inspect(error)}")
        {:stop, :shutdown, state}
    end
  end

  # ---- receive ICE Candidate from client
  def handle_cast({:receive_signaling_msg, %{"type" => "ice"} = msg}, %{curr: %{pc: pc}} = state) do
    case msg["candidate"] do
      nil ->
        {:noreply, state}

      candidate ->
        candidate = ICECandidate.from_json(candidate)
        :ok = PeerConnection.add_ice_candidate(pc, candidate)
        {:noreply, state}
    end
  end

  def handle_cast({:receive_signaling_msg, msg}, state) do
    Logger.error("Server: unexpected msg: #{inspect(msg)}")
    {:stop, :shutdown, state}
  end

  # ---- send ICE Candidate to client
  @impl true
  def handle_info({:ex_webrtc, _pc, {:ice_candidate, candidate}}, state) do
    candidate = ICECandidate.to_json(candidate)
    send(state.curr.channel, {:signaling, %{"type" => "ice", "candidate" => candidate}})
    {:noreply, state}
  end

  ###### get the tracks from the client to match on "rtp" packets
  def handle_info({:ex_webrtc, pc, {:track, %{id: id, kind: :audio}}}, state) do
    state =
      Map.update!(state, pc, fn v -> Map.merge(v, %{client_a_track_id: id}) end)

    {:noreply, state}
  end

  def handle_info({:ex_webrtc, pc, {:track, %{id: id, kind: :video}}}, state) do
    state =
      Map.update!(state, pc, fn v -> Map.merge(v, %{client_v_track_id: id}) end)

    {:noreply, state}
  end

  ###### get the received packets from the client and redirect to the other PC
  def handle_info({:ex_webrtc, pc, {:rtp, id, packet}}, state)
      when state.all_connected == true do
    # good only for 2 peers.
    [pc2] = Map.keys(state) -- [pc, :curr, :all_connected]

    cond do
      state[pc].client_v_track_id == id ->
        :ok = PeerConnection.send_rtp(pc2, state[pc2].serv_v_track_id, packet)

      state[pc].client_a_track_id == id ->
        :ok = PeerConnection.send_rtp(pc2, state[pc2].serv_a_track_id, packet)
    end

    {:noreply, state}
  end

  # ---- RTCP
  def handle_info({:ex_webrtc, _pc, {:rtcp, _packets}}, state) when state.all_connected == true do
    # [pc2] = Map.keys(state) -- [pc, :curr, :all_connected]

    # for packet <- packets do
    #   case packet do
    #     %ExRTCP.Packet.PayloadFeedback.PLI{} ->
    #       IO.puts("--> SEND_PLI--> to: #{inspect(pc2)}")
    #       :ok = PeerConnection.send_pli(pc2, state[pc2].client_v_track_id)

    #     _other ->
    #       :ok
    #   end
    # end

    {:noreply, state}
  end

  # ---- connection state
  def handle_info({:ex_webrtc, pc, {:connection_state_change, :connected}}, state) do
    # send info flash in LV
    send(state.curr.lv_pid, :user_connected)

    if map_size(state) == 4 do
      Logger.warning("--> Server: Both inputs are successfully connected")
      [pc2] = Map.keys(state) -- [pc, :curr, :all_connected]

      :ok = PeerConnection.send_pli(pc2, state[pc2].client_v_track_id)
      {:noreply, Map.put(state, :all_connected, true)}
    else
      {:noreply, state}
    end
  end

  def handle_info({:ex_webrtc, _pc, {:connection_state_change, new_state}}, state) do
    Logger.debug("--> Server: Connection state changed: #{new_state}")
    {:noreply, state}
  end

  # collect all
  def handle_info({:ex_webrtc, _, _}, state) do
    {:noreply, state}
  end

  # response from monitor on channel_pid
  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    {:stop, reason, state}
  end

  ########################################################################################
  defp setup_transceivers(pc) do
    video = MediaStreamTrack.new(:video)
    audio = MediaStreamTrack.new(:audio)
    {:ok, _v_sender} = PeerConnection.add_track(pc, video)
    {:ok, _sender} = PeerConnection.add_track(pc, audio)

    %{serv_v_track_id: video.id, serv_a_track_id: audio.id}
  end

  defp gather_candidates(pc) do
    receive do
      {:ex_webrtc, ^pc, {:ice_gathering_state_change, :complete}} -> :ok
    after
      1000 -> {:error, :timeout}
    end
  end
end
