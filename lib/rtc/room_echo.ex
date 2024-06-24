defmodule Rtc.RoomEcho do
  use GenServer, restart: :temporary

  @moduledoc """
  The Room module is responsible for managing the Echo connection.
  The ExWebRTC server sneds back to the connected client ti's media streams.

  It is dynamically supervised by the DynSup.
  The Lobby GenServer starts a RoomEcho for each user.
  """

  require Logger

  alias ExWebRTC.{ICECandidate, PeerConnection, SessionDescription, MediaStreamTrack}
  alias ExWebRTC.RTP.VP8Depayloader

  @ice_servers [
    %{urls: "stun:stun.l.google.com:19302"},
    %{urls: "stun:stun.l.google.com:5349"},
    %{urls: "stun:stun1.l.google.com:3478"}
  ]

  defp id(room_id), do: {:via, Registry, {Rtc.Reg, room_id}}

  def start_link(args) do
    rid = Keyword.get(args, :room_id)
    GenServer.start_link(__MODULE__, args, name: id(rid))
  end

  def connect(room_id: room_id, channel: channel, user_id: user_id),
    do: GenServer.call(id(room_id), {:connect, channel, user_id})

  def receive_signaling_msg(room_id, msg),
    do: GenServer.cast(id(room_id), {:receive_signaling_msg, msg})

  # debug
  def state(room_id), do: GenServer.call(id(room_id), :state)
  def running?(room_id), do: GenServer.whereis(id(room_id)) != nil

  # --------------------------------------------------------------------------------------------
  @impl true
  def init(args) do
    lv_pid = Keyword.get(args, :lv_pid)
    rid = Keyword.get(args, :room_id)
    uid = Keyword.get(args, :user_id)

    Logger.debug("Starting Room:#{rid} GS, #{inspect(self())}")

    # send(self(), :init_streamer)

    {:ok,
     %{
       room_id: rid,
       user_id: uid,
       streamer: nil,
       pc: nil,
       lv_pid: lv_pid,
       channel: nil,
       client_video_track: nil,
       client_audio_track: nil,
       video_depayloader: VP8Depayloader.new(),
       i: 0,
       time: System.monotonic_time()
     }, {:continue, :init_streamer}}
  end

  @impl true
  # caoont start a GenServer from a GenServer!
  def handle_continue(:init_streamer, state) do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        Rtc.DynSup,
        {Rtc.FFmpegStreamer, [type: "echo", user_id: state.user_id]}
      )

    Process.link(pid)
    {:noreply, %{state | streamer: pid}}
  end

  @impl true
  def handle_call({:connect, channel_pid, user_id}, _from, state) do
    Process.monitor(channel_pid)
    {:ok, pc} = PeerConnection.start_link(ice_servers: @ice_servers)

    # direction: :sendrecv since we receive tracks from client and send them back
    new_tracks = setup_transceivers(pc)

    state =
      state
      |> Map.merge(%{channel: channel_pid, pc: pc, user_id: user_id})
      |> Map.merge(new_tracks)

    Logger.info(
      "--> Room Echo #{inspect(state.room_id)} , process #{inspect(self())}, starts PC #{inspect(pc)}}, channel #{inspect(channel_pid)}"
    )

    {:reply, :connected, state}
  end

  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  # -- receive Offer from client
  def handle_cast({:receive_signaling_msg, %{"type" => "offer"} = msg}, state) do
    with desc <-
           SessionDescription.from_json(msg["sdp"]),
         :ok <-
           PeerConnection.set_remote_description(state.pc, desc),
         {:ok, answer} <-
           PeerConnection.create_answer(state.pc),
         :ok <-
           PeerConnection.set_local_description(state.pc, answer),
         :ok <-
           gather_candidates(state.pc) do
      Logger.debug("--> Server sends Answer to remote")

      #  the 'answer' is formatted into a struct, which can't be read by the JS client
      sent_answer = %{
        "type" => "answer",
        "sdp" => %{type: answer.type, sdp: answer.sdp},
        "from" => msg["from"]
      }

      send(state.channel, {:signaling, sent_answer})
      {:noreply, state}
    else
      error ->
        Logger.error("Server: Error creating answer: #{inspect(error)}")
        {:stop, :shutdown, state}
    end
  end

  # -- receive ICE Candidate from client
  def handle_cast({:receive_signaling_msg, %{"type" => "ice"} = msg}, state) do
    case msg["candidate"] do
      nil ->
        {:noreply, state}

      candidate ->
        candidate = ICECandidate.from_json(candidate)
        :ok = PeerConnection.add_ice_candidate(state.pc, candidate)
        Logger.debug("--> Server processes remote ICE")
        {:noreply, state}
    end
  end

  def handle_cast({:receive_signaling_msg, msg}, state) do
    Logger.warning("Server: unexpected msg: #{inspect(msg)}")
    {:stop, :shutdown, state}
  end

  @impl true
  # -- send ICE Candidate to client
  def handle_info({:ex_webrtc, _pc, {:ice_candidate, candidate}}, state) do
    candidate = ICECandidate.to_json(candidate)
    send(state.channel, {:signaling, %{"type" => "ice", "candidate" => candidate}})
    Logger.debug("--> Server sends ICE to remote")
    {:noreply, state}
  end

  ########################################################################################
  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) when pid == state.channel do
    {:stop, reason, state}
  end

  ####### receive the client track_id per kind and save it in the state

  def handle_info({:ex_webrtc, _pc, {:track, %{kind: :audio} = client_audio_track}}, state) do
    {:noreply, %{state | client_audio_track: client_audio_track}}
  end

  def handle_info({:ex_webrtc, _pc, {:track, %{kind: :video} = client_video_track}}, state) do
    {:noreply, %{state | client_video_track: client_video_track}}
  end

  ########################################################################################
  ## ECHO SERVER

  # the server receives packets from the client.
  # We pick the packets with kind :audio by matching the received track_id with the state.client_audio_track.id
  # We send these packets to the PeerConnection under the server audio track id.

  def handle_info(
        {:ex_webrtc, pc, {:rtp, client_track_id, packet}},
        %{client_audio_track: %{id: client_track_id, kind: :audio}} = state
      ) do
    PeerConnection.send_rtp(pc, state.serv_audio_track.id, packet)
    {:noreply, state}
  end

  def handle_info(
        {:ex_webrtc, pc, {:rtp, client_track_id, packet}},
        %{client_video_track: %{id: client_track_id, kind: :video}} = state
      ) do
    PeerConnection.send_rtp(pc, state.serv_video_track.id, packet)

    state = handle_v_paquet(packet, state)
    {:noreply, state}
  end

  def handle_info({:ex_webrtc, pc, {:connection_state_change, :connected}}, state) do
    send(state.lv_pid, :user_connected)
    Logger.debug("Server to client PeerConnection #{inspect(pc)} successfully connected")
    {:noreply, state}
  end

  # debug
  def handle_info({:ex_webrtc, _pc, {:connection_state_change, new_state}}, state) do
    Logger.debug("--> Connection state changed: #{new_state}")
    {:noreply, state}
  end

  def handle_info({:ex_webrtc, _pc, {:rtcp, _, _}}, state) do
    Logger.debug("--> RTCP packet received").{:noreply, state}
  end

  # collect all
  def handle_info({:ex_webrtc, _, _}, state) do
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, _, reason}, state) do
    Logger.debug("Process terminated with reason #{inspect(reason)}")
    {:noreply, state}
  end

  ########################################################################################
  defp handle_v_paquet(packet, %{i: _i} = state) do
    case VP8Depayloader.write(state.video_depayloader, packet) do
      {:ok, d} ->
        %{state | video_depayloader: d}

      {:ok, _frame, d} ->
        # once we get the frame, we work on 1 out of X frames
        # send(state.streamer, {:echo, frame, self()})

        %{state | video_depayloader: d}

      {:error, _msg} ->
        # Logger.error("Error depayloading video: #{msg}")
        state
    end
  end

  defp gather_candidates(pc) do
    receive do
      {:ex_webrtc, ^pc, {:ice_gathering_state_change, :complete}} -> :ok
    after
      1000 -> {:error, :timeout}
    end
  end

  defp setup_transceivers(pc) do
    video = MediaStreamTrack.new(:video)
    audio = MediaStreamTrack.new(:audio)
    {:ok, _sender} = PeerConnection.add_track(pc, video)
    {:ok, _sender} = PeerConnection.add_track(pc, audio)

    %{serv_video_track: video, serv_audio_track: audio}
  end
end
