Mix.install([
	{:plug, "~> 1.6"},
	{:plug_crypto, "~> 1.2"},
	{:bandit, "~> 1.5"},
  {:websock_adapter, "~> 0.5"},
	{:ex_cmd, "~> 0.12"},
	{:evision, "~> 0.2"},
])

defmodule HomeController do
  def serve_homepage(conn, %{csrf_token: token}) do
    html = EEx.eval_file("./index.html.heex", csrf_token: token)
    Plug.Conn.send_resp(conn, 200, html)
  end

	def serve_js(conn, _) do
		Plug.Conn.send_file(conn, 200, "main.js")
	end
end

defmodule WebRouter do
	use Plug.Router

	@session_options [
		store: :cookie, key: "_my_key", signing_salt: "my_salt", table: :session,
		secret_key_base: String.duplicate("a", 64)
	]

	plug Plug.Session, @session_options
	plug :fetch_session
	plug Plug.CSRFProtection
	plug(:match)
  plug(:dispatch)


	get "/" do
		token = Plug.CSRFProtection.get_csrf_token()

		conn
		|> Plug.Conn.fetch_session()
		|> Plug.Conn.put_session(:csrf_token, token)
		
		HomeController.serve_homepage(conn, %{csrf_token: token})
	end

	get "/js/main.js" do
		HomeController.serve_js(conn, [])
	end
	
	get "/socket" do
		conn
		|> validate_csrf_token()
		|> WebSockAdapter.upgrade(WebSocketHandler, [], timeout: 60_000)
		|> halt()
	end
	
	match _ do
		send_resp(conn, 404, "not found")
	end

	defp validate_csrf_token(conn) do
		%{"_csrf_token" => session_token} = 
			conn 
			|> Plug.Conn.fetch_session() 
			|> Plug.Conn.get_session()

		%Plug.Conn{query_params: %{"csrf_token" => params_token}} = 
			Plug.Conn.fetch_query_params(conn)

    if params_token == session_token do
      conn
    else
      Plug.Conn.halt(conn)
    end
  end
end


defmodule ImageProcessor do
	def load_haar_cascade do
		haar_path = 
			Path.join(
				:code.priv_dir(:evision),
				"share/opencv4/haarcascades/haarcascade_frontalface_default.xml"
			)
		
		Evision.CascadeClassifier.cascadeClassifier(haar_path)
	end

  def detect_and_draw_faces(file, face_detector) do
	input_path = Path.join("input",file)
	output_path = Path.join("output",file)

	frame = 
		Evision.imread(input_path)
	# convert to grey-scale
	grey_img = 
		Evision.cvtColor(frame, Evision.ImreadModes.cv_IMREAD_GRAYSCALE())
	# detect faces
	faces = 
		Evision.CascadeClassifier.detectMultiScale(face_detector, grey_img)
		
	# draw rectangles found on the original frame
	result_frame = 
		Enum.reduce(faces, frame, fn {x, y, w, h}, mat ->
			Evision.rectangle(mat, {x, y}, {x + w, y + h}, {0, 255,0}, thickness: 2)
		end)
		
	Evision.imwrite(output_path, result_frame)
	:ok = File.rm!(input_path)
  end
end

##################################################################################
# ffmpeg [GeneralOptions] [InputFileOptions] -i input [OutputFileOptions] output #
##################################################################################

defmodule FrameCapturer do
	def start_ffmpeg(frame_rate, resolution, frame_pattern) do
		build_frames =
			~w(ffmpeg -loglevel debug -i pipe:0 -framerate #{frame_rate} -video_size #{resolution} -thread_type slice #{frame_pattern})
		{:ok, pid_into_file} = ExCmd.Process.start_link(build_frames)
		pid_into_file
	end
    # w(ffmpeg -loglevel warning  -i pipe:0  -framerate 30 -video_size 640x480 -y in/test_%004d.jpg)
end

defmodule VideoSegmenter do
  require Logger

	def create_video_segment(frame_files, frame_rate) do
    Logger.debug("FFmpeg_rebuild ----#{ length(frame_files)}")

		timestamp = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
		segment = Path.join("output", "out_#{timestamp}.webm")
		ffmpeg_rebuild_cmd = 
			~w(ffmpeg -loglevel info -f image2pipe  -framerate #{frame_rate} -i pipe:0  -c:v libvpx -b:v 1M -f webm -deadline realtime  -y #{segment})
      
      # version mp4 not working???
    	# ~w(ffmpeg -loglevel warning  -f image2pipe  -framerate 30 -i pipe:0 -c:v libx264 -preset slow -crf 22 -y #{curr_mp4})

      {:ok, pid} = 
        ExCmd.Process.start_link(ffmpeg_rebuild_cmd)
        
    for file <- frame_files do
      :ok = ExCmd.Process.write(pid, File.read!(Path.join("output", file)))
    end
    :ok = ExCmd.Process.close_stdin(pid)
    ExCmd.Process.await_exit(pid, 100)
    
    # :ok = Enum.each(frame_files, &File.rm(Path.join("output", &1)))
    segment
	end
end
  

defmodule WebSocketHandler do
	@behaviour WebSock

	@chunk_duration 10
	@frame_rate 30
	@resolution "640x480"
	@frame_pattern "input/test_%04d.jpg"

	require Logger

	@impl true
	def init(_args) do
		Logger.debug("INITIALIZED------")
		pid_into_file = FrameCapturer.start_ffmpeg(@frame_rate, @resolution, @frame_pattern)

		state = %{
			face_detector: ImageProcessor.load_haar_cascade(),
			pid_into_file: pid_into_file, 
      map_list: MapSet.new(),
			queue: :queue.new(),
      frame_rate: @frame_rate,
			webm: nil,
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

		case File.ls!("input") do
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

          webm_segment = 
            VideoSegmenter.create_video_segment(list, frame_rate)
          Enum.each(list, &File.rm(Path.join("input", &1)))
          webm_segment
      end)

    {:ok, %{state | map_list: MapSet.new(), ref: ref, chunk_id: 0}}
  end
	
	def handle_info(:ffmpeg_rebuild, state) do
		{:ok, state}
	end

	# return from Task.async rebuild
	def handle_info({ref, webm_segment}, %{ref: ref} = state) do
		send(self(), {:send_to_browser, webm_segment})
		{:ok, state}
	end

	def handle_info({:send_to_browser, webm_segment}, state) do
		Logger.debug("SENDING TO BROWSER...#{webm_segment}")
		data = File.read!(webm_segment)
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

webserver = {Bandit, plug: WebRouter, port: 4000}
{:ok, _} = Supervisor.start_link([webserver], strategy: :one_for_one)
Process.sleep(:infinity)

