
defmodule WebSocketHandler do
	@behaviour WebSock

	@chunk_duration 10
	@frame_rate 30
	@resolution "640x480"
	

	require Logger

	@impl true
	def init(_args) do
		Logger.debug("INITIALIZED------")
		pid_into_file = 
			FrameCapturer.start_ffmpeg(@frame_rate, @resolution)

		state = %{
			face_detector: ImageProcessor.load_haar_cascade(),
			pid_into_file: pid_into_file, 
      map_list: MapSet.new(),
			queue: :queue.new(),
      frame_rate: @frame_rate,
			# webm: nil,
			chunk_id: 1,
			ref: nil
		}

		{:ok, state}
	end

	@impl true
	def handle_in({"stop", [opcode: :text]}, state) do
		Logger.warning("STOPPED------")
		:ok = gracefully_stop(state.pid_into_file)
		{:stop, :normal, state}
	end

	def handle_in({msg, [opcode: :binary]}, state) do
		Logger.debug("received data ---------------#{state.chunk_id}")

		%{chunk_id: chunk_id} = state
		:ok = ExCmd.Process.write(state.pid_into_file, msg)
		send(self(), :ffmpeg_process)
		{:ok, %{state | chunk_id: chunk_id+1}}
	end

	@impl true
	def handle_info({:EXIT, pid, reason}, state) do
		Logger.debug("EXITED: #{inspect(pid)}: #{inspect(reason)}")
		{:ok, state}
	end


	def handle_info(:ffmpeg_process, state) do
		%{queue: queue, map_list: map_list}= state

		case File.ls!("priv/input") do
			[] -> 
				{:ok, state}
			files ->
        new_files = 
          MapSet.difference(MapSet.new(files), map_list)

				# MapSet.size(new_files) |> IO.inspect()
        new_queue = :queue.in(MapSet.to_list(new_files), queue) 
        map_list = MapSet.union(new_files, map_list)
				send(self(), :process_queue)
				{:ok, %{state | queue: new_queue, map_list: map_list}}
		end
	end

	def handle_info(:process_queue,state) do
		%{queue: queue, face_detector: face_detector} = state
		case :queue.out(queue) do
			{{:value, files}, new_queue}  ->
				Task.async_stream(files, 
          fn file -> 
					  ImageProcessor.detect_and_draw_faces(file, face_detector)
				  end, 
          max_concurreny: 4, 
          ordered: false
        )
				|> Stream.run()
        
				send(self(), :process_queue)
				{:ok,%{state | queue: new_queue}}
		
			{:empty, _} ->
				send(self(), :ffmpeg_rebuild)
				{:ok, %{state | queue: :queue.new()}}
		end
	end

  def handle_info(:ffmpeg_rebuild, %{chunk_id: @chunk_duration} = state) do
    %{map_list: map_list, frame_rate: frame_rate} = state
    
    %{ref: ref} = 
      Task.async(fn -> 
        list = 
          MapSet.to_list(map_list) 
          |> Enum.sort()

          # webm_segment = 
          #   VideoSegmenter.create_video_segment(list, frame_rate)
					playlist = 
						VideoSegmenter.create_video_segment_and_playlist(list, frame_rate)
						
          Enum.each(list, &File.rm(Path.join("priv/input", &1)))
          playlist
      end)

    {:ok, %{state | map_list: MapSet.new(), ref: ref, chunk_id: 0}}
  end
	
	def handle_info(:ffmpeg_rebuild, state) do
		{:ok, state}
	end

	# return from Task.async rebuild
	def handle_info({ref, playlist}, %{ref: ref} = state) do
		send(self(), {:send_to_browser, playlist})
		{:ok, state}
	end

	def handle_info({:send_to_browser,playlist}, state) do
		Logger.debug("SENDING TO BROWSER...#{playlist}")
		data = File.read!(playlist)
		{:push, {:binary, data}, state}
	end

	def handle_info({:DOWN, ref, :process, _, :normal}, %{ref: ref} = state) do
		IO.puts "received DOWN"
		{:ok, %{state | ref: nil}}
	end

	def handle_info(msg, state) do
		Logger.warning( "UNHANDLED: #{inspect(msg)}")
		{:ok, state}
	end

	@impl true
	def terminate(reason, state) do
		IO.puts("TERMINATED: #{inspect(reason)}")
		{:stop, :normal, state}
	end

	defp gracefully_stop(pid) do
		if is_pid(pid) && Process.alive?(pid) do
			:ok = ExCmd.Process.close_stdin(pid)
			ExCmd.Process.await_exit(pid, 1_000)
			ExCmd.Process.stop(pid)
		end
		:ok
	end
end