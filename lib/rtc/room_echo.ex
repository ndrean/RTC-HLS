defmodule Rtc.RoomEcho do
  use GenServer, restart: :temporary

  @moduledoc """
  The Room module is responsible for managing the Echo connection.
  The ExWebRTC server sneds back to the connected client ti's media streams.

  It is dynamically supervised by the DynSup.
  The Lobby GenServer starts a RoomEcho for each user.
  """

  require Logger

  alias Rtc.FFmpegStreamer

  alias ExWebRTC.{
    ICECandidate,
    PeerConnection,
    RTPCodecParameters,
    SessionDescription,
    MediaStreamTrack
  }

  alias ExWebRTC.RTP.VP8.Depayloader

  @ice_servers [
    %{urls: "stun:stun.l.google.com:19302"},
    %{urls: "stun:stun.l.google.com:5349"},
    %{urls: "stun:stun1.l.google.com:3478"}
  ]

  @video_codecs [
    %RTPCodecParameters{
      payload_type: 96,
      mime_type: "video/VP8",
      clock_rate: 90_000
    }
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

    ffmpeg_pid = FFmpegStreamer.get_ffmpeg_pid(%{user_id: uid, type: "echo"})

    Process.link(ffmpeg_pid)

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
       video_depayloader: Depayloader.new(),
       #  video_decoder: Xav.Decoder.new(:vp8),
       i: 1,
       t: System.monotonic_time(:microsecond),
       ffmpeg: ffmpeg_pid
     }}
  end

  @impl true
  def handle_call({:connect, channel_pid, user_id}, _from, state) do
    Process.monitor(channel_pid)
    {:ok, pc} = PeerConnection.start_link(ice_servers: @ice_servers, video_codecs: @video_codecs)

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
        {:ex_webrtc, pc, {:rtp, client_track_id, _, packet}},
        %{client_audio_track: %{id: client_track_id, kind: :audio}} = state
      ) do
    PeerConnection.send_rtp(pc, state.serv_audio_track.id, packet)
    {:noreply, state}
  end

  def handle_info(
        {:ex_webrtc, pc, {:rtp, client_track_id, _, packet}},
        %{client_video_track: %{id: client_track_id, kind: :video}} = state
      ) do
    PeerConnection.send_rtp(pc, state.serv_video_track.id, packet)
    state = handle_paquet(packet, state)
    {:noreply, state}
  end

  def handle_info({:ex_webrtc, pc, {:connection_state_change, :connected}}, state) do
    send(state.lv_pid, :user_connected)
    # sdp = PeerConnection.get_remote_description(pc).sdp
    # Regex.scan(~r/a=rtpmap:([a-zA-Z0-9\s]+)/, sdp) |> dbg()

    PeerConnection.get_transceivers(pc)
    |> Enum.find(&(&1.kind == :video))
    |> then(fn %{receiver: receiver} ->
      dbg(receiver.codec.mime_type)

      Logger.warning(
        "PeerConnection successfully connected, video using #{inspect(receiver.codec.mime_type)}"
      )
    end)

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
  defp handle_paquet(packet, state) do
    %{i: i, lv_pid: _lv_pid, ffmpeg: ffmpeg} = state

    case Depayloader.write(state.video_depayloader, packet) do
      {:ok, d} ->
        %{state | video_depayloader: d}

      {:ok, frame, d} ->
        n = i + 1
        q = 30

        if Integer.mod(i, q) == 0 do
          t = System.monotonic_time(:microsecond)

          Logger.debug(%{
            count: i,
            size: Float.round(byte_size(frame) * 8 / 1_000, 1),
            fps: round(q * 1_000_000 / (t - state.t))
          })

          # File.write("/Users/nevendrean/code/elixir/RTC-HLS/frame.vp8", frame)
          :ok = ExCmd.Process.write(ffmpeg, frame)
          # {:ok, data} = ExCmd.Process.read(ffmpeg) |> dbg()
          # ExCmd.stream!(~w(ffmpeg -i pipe:0 -f vpx -c:v copy -f webm pipe:1), input: frame, log: true)
          # |> Stream.into(File.stream!("demo/test.webm"))
          %{state | video_depayloader: d, i: n, t: t}
        else
          %{state | video_depayloader: d, i: n}
        end

        # {:error, msg} ->
        #   Logger.error("Error depayloading video: #{msg}")
        #   state
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
    media_stream_id = MediaStreamTrack.generate_stream_id()
    video = MediaStreamTrack.new(:video, [media_stream_id])
    audio = MediaStreamTrack.new(:audio, [media_stream_id])
    {:ok, _sender} = PeerConnection.add_track(pc, video)
    {:ok, _sender} = PeerConnection.add_track(pc, audio)

    %{serv_video_track: video, serv_audio_track: audio}
  end
end
