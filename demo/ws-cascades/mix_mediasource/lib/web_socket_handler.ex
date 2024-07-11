
defmodule WebSocketHandler do
	@behaviour WebSock

	@duration 5
	@frame_rate 30
	@resolution "640x480"
	

	require Logger

	@impl true
	def init(_args) do
		Logger.debug("INITIALIZED------")

		{:ok, watcher_pid} = GenServer.start(FileWatcher, self())

		{pid_capture, pid_segment} = 
			FFmpegProcessor.start(@frame_rate, @resolution, @duration)
			|> dbg()

		state = %{
			face_detector: ImageProcessor.load_haar_cascade(),
			pid_capture: pid_capture,
			pid_segment: pid_segment,
			pid_watcher: watcher_pid,
      map_list: MapSet.new(),
			queue: :queue.new(),
      frame_rate: @frame_rate,
			chunk_id: 1,
			ref: nil,
			init: true
		}

		{:ok, state}
	end

	@impl true
	def handle_in({"stop", [opcode: :text]}, state) do
		Logger.warning("STOPPED------")
		:ok = gracefully_stop(state.pid_capture)
		:ok = gracefully_stop(state.pid_segment)
		:ok = GenServer.stop(state.pid_watcher)
		{:stop, :normal, state}
	end

	# we receive the binary data from the browser
	def handle_in({msg, [opcode: :binary]}, state) do
		Logger.debug("received data ---------------#{state.chunk_id}")

		%{pid_capture: pid_capture, chunk_id: chunk_id} = state

		# Write the received binary data to the FFmpeg capture process
		:ok = ExCmd.Process.write(pid_capture, msg)

		send(self(), :ffmpeg_process)
		{:ok, %{state | chunk_id: (chunk_id + 1)}}
	end

	@impl true
	

	# check if there are new files in the input directory and enqueue them
	def handle_info(:ffmpeg_process, state) do
		%{queue: queue, map_list: map_list}= state

		case File.ls!("priv/input") do
			[] -> 
				{:ok, state}
			files ->
        new_files = 
          MapSet.difference(MapSet.new(files), map_list)

				#MapSet.size(new_files) |> IO.inspect(label: "NEW FILES")

        new_queue = :queue.in(MapSet.to_list(new_files), queue) 
        map_list = MapSet.union(new_files, map_list)
				#MapSet.size(map_list) |> IO.inspect(label: "MAP LIST")
				send(self(), :process_queue)
				{:ok, %{state | queue: new_queue, map_list: map_list}}
		end
	end

	# process the queue of files and run async_stream
	# to detect and draw faces on each file and create a new file
	def handle_info(:process_queue,state) do
		%{queue: queue, face_detector: face_detector} = state
		case :queue.out(queue) do
			{{:value, files}, new_queue}  ->
				:ok = 
					Task.async_stream(files, 
          fn file -> 
					  :ok = ImageProcessor.detect_and_draw_faces(file, face_detector)
				  end, 
          max_concurreny: System.schedulers_online(), 
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

	# every @duration seconds (1 chunk per second as set Javascript mediaRecorder.start(1000))
	# we rebuild the video with the new frames. We have to order the frames by name to 
	# rebuild the video in the correct order
  def handle_info(:ffmpeg_rebuild, %{chunk_id: @duration} = state) do
    %{map_list: map_list, pid_segment: pid_segment} = state
    
		list = 
			MapSet.to_list(map_list) 
			|> Enum.sort()

    %{ref: ref} = 
      Task.async(fn -> 

				for file <- list do
					ExCmd.Process.write(pid_segment, File.read!(Path.join("priv/output", file)))
				end
				Enum.each(list, &File.rm(Path.join("priv/output", &1)))
			end)

    {:ok, %{state | map_list: MapSet.new(), chunk_id: 0, ref: ref}}
  end

	# If the chunk_id does not match @duration, just pass through
	def handle_info(:ffmpeg_rebuild, state) do
		{:ok, state}
	end

	

	# file_watcher: the first time the playlist file is created, we send a message to the browser
	def handle_info(:playlist_created, %{init: true} = state) do
		Logger.warning("PLAYLIST CREATED")
		{:push, {:text, "playlist_ready"}, %{state | init: false}}
	end

	# we don't handle other events on the playlist file as the Hls.js library will take care of it
	def handle_info(:playlist_created, state) do
		{:ok, state}
	end

	# process messages----------------------------------------------------------------

	# return from Task.async rebuild
	def handle_info({ref, :ok}, %{ref: ref} = state) do
		{:ok, state}
	end

	# return from Task.async rebuild
	def handle_info({:DOWN, ref, :process, _, :normal}, %{ref: ref} = state) do
		Logger.debug("FFmpeg rebuild task finished")
		{:ok, %{state | ref: nil}}
	end

	def handle_info({:EXIT, pid, reason}, state) do
		Logger.debug("EXITED: #{inspect(pid)}: #{inspect(reason)}")
		{:ok, state}
	end

	# if any other message is received, log it
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