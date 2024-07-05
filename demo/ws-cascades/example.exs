Mix.install([
	{:plug, "~> 1.6"},
	{:bandit, "~> 1.5"},
  {:websock_adapter, "~> 0.5"},
	{:ex_cmd, "~> 0.12"},
	{:evision, "~> 0.2"}
])

defmodule Processor do
	def haar do
    haar_path = 
      Path.join(
        :code.priv_dir(:evision),
        "share/opencv4/haarcascades/haarcascade_frontalface_default.xml"
      )
          
    Evision.CascadeClassifier.cascadeClassifier(haar_path)
  end

  def contour(file, model) do
		curr_path = Path.join("in",file)

		frame = 
			Evision.imread(curr_path)
		# convert to grey-scale
		grey_img = 
			Evision.cvtColor(frame, Evision.ImreadModes.cv_IMREAD_GRAYSCALE())
		# detect faces
		faces = 
			Evision.CascadeClassifier.detectMultiScale(model, grey_img)
			
		# draw rectangles found on the original frame
		img = 
			Enum.reduce(faces, frame, fn {x, y, w, h}, mat ->
				Evision.rectangle(mat, {x, y}, {x + w, y + h}, {0, 0, 255}, thickness: 2)
			end)
			
		Evision.imwrite(Path.join("out", file), img)
		:ok = File.rm!(curr_path)
  end
end


defmodule Controller do
  def index(conn, _) do
    Plug.Conn.send_file(conn, 200, "./index.html")
  end
end

defmodule Router do
	use Plug.Router

	plug(:match)
  plug(:dispatch)

	get "/" do
		Controller.index(conn, [])
	end
	
	get "/socket" do
		conn
		|> WebSockAdapter.upgrade(WsServer, [], timeout: 60_000)
		|> halt()
	end
	
	match _ do
		send_resp(conn, 404, "not found")
	end
end

defmodule WsServer do
	@behaviour WebSock

	@impl true
	def init(_args) do
		
		# command to save video into files of frames with ExCmd.Process
		get_frames = 
      ~w(ffmpeg -i pipe:0  -r 30 -video_size 640x480 -y in/test_%004d.jpg)
			
	
		rebuild_frames = 
			~w(ffmpeg -framerate 30 -f image2pipe -i pipe:0 -c:v libx264 -preset slow -crf 22 -y out/out.mp4)

		# command to save video into files of frames with ExCmd.stream!
		
		i=0
		fn_file = fn i -> 
			~w(ffmpeg -i pipe:0  -r 30 -video_size 640x480 -y in/#{i}-test_%004d.jpg)
		end
    
    {:ok, pid_into_file} = ExCmd.Process.start_link(get_frames, log: true)
		{:ok, pid_rebuild} = ExCmd.Process.start_link(rebuild_frames, log: true)

		state = %{
			i: i, 
			model: Processor.haar(),
			pid_into_file: pid_into_file, 
			pid_rebuild: pid_rebuild,
			fn_file: fn_file, 
			cmd_file: get_frames,
			queue: :queue.new(),
			processed: []
		}

		{:ok, state}
	end

	@impl true
	def handle_in({"stop", [opcode: :text]}, state) do
		IO.puts ("STOPPED------")
		ExCmd.Process.close_stdin(state.pid_into_file)
		ExCmd.Process.await_exit(state.pid_into_file)
		ExCmd.Process.close_stdin(state.pid_rebuild)
		ExCmd.Process.await_exit(state.pid_rebuild)
		{:stop, :normal, state}
	end

	# "type" is set in the browser and enables different ways to use ExCmd.Process or ExCmd.Stream
	def handle_in({type, [opcode: :text]}, state) do
		{:ok, Map.put(state, :type, type)}
	end

	def handle_in({msg, [opcode: :binary]}, state) do
		case state.type do
			"file-proc" -> 
				IO.puts("received data ---------------")
				:ok = ExCmd.Process.write(state.pid_into_file, msg)
				send(self(), :ffmpeg_processed)
				{:ok, state}

			# unsuccessful version with ExCmd.stream!  ???
			"file-stream" -> 
				IO.puts("file-stream")
				i=0
				:ok = 
					ExCmd.stream!(state.fn_file.(i), input: msg, log: true)
					|> Stream.run()

				{:ok, Map.put(state, :i, i+1)}
		end
	end

	@impl true
	def handle_info({:EXIT, _pid, _reason}, state) do
		#IO.puts("EXITED: #{inspect(pid)}: #{inspect(reason)}")
		{:ok, state}
	end


	def handle_info(:ffmpeg_processed, state) do
		%{queue: queue}= state
		case File.ls!("in") do
			[] -> 
				{:ok, state}
			files ->
				send(self(), :process_queue)
				{:ok, Map.put(state, :queue, :queue.in(files, queue))}
		end
	end

	def handle_info(:process_queue,state) do
		%{queue: queue, model: model} = state
		case :queue.out(queue) do
			{{:value, files}, new_queue}  ->
				Task.async_stream(files, fn file -> 
					Processor.contour(file, model)
				end)
				|> Stream.run()
				send(self(), :process_queue)
				{:ok,%{state | queue: new_queue, processed: files}}
			{:empty, _} ->
				send(self(), :ffmpeg_rebuild)
				{:ok, state}
		end
	end

	def handle_info(:ffmpeg_rebuild, state) do
		%{processed: processed, pid_rebuild: pid_rebuild} = state
		processed = Enum.sort(processed)
		for file <- processed do
			data = File.read!(Path.join("out", file))
			:ok = ExCmd.Process.write(pid_rebuild,data)
		end
		send(self(), :send_to_browser)
		{:ok, %{state | processed: []}}
	end

	def handle_info(:send_to_browser, state) do
		# {:reply, :ok, {:binary, <<>>}, state}
		{:ok, state}
	end

	def handle_info(_msg, state) do
		{:ok, state}
	end

	@impl true
	def terminate(reason, state) do
		IO.puts("TERMINATED: #{inspect(reason)}")
		ExCmd.Process.close_stdin(state.pid_into_file)
    ExCmd.Process.await_exit(state.pid_into_file)
		ExCmd.Process.close_stdin(state.pid_rebuild)
		ExCmd.Process.await_exit(state.pid_rebuild)
		{:ok, state}
	end
end

webserver = {Bandit, plug: Router, port: 4000}
{:ok, _} = Supervisor.start_link([webserver], strategy: :one_for_one)
Process.sleep(:infinity)


# /* for later.....
# let mediaSource = new MediaSource();
# let sourceBuffer;
# let queue = [];
# let mediaSourceReady = false;

# video2.src = URL.createObjectURL(mediaSource);
# mediaSource.addEventListener("sourceopen", () => {
# 	sourceBuffer = mediaSource.addSourceBuffer("video/webm; codecs=vp8, vorbis");
# 	mediaSourceReady = true;
# 	if (queue.length > 0) {
# 		queue.forEach((data) => {
# 			sourceBuffer.appendBuffer(data);
# 		});
# 		queue = [];
# 	}
# })

# socket.onmessage = async ({data}) => {
# 	sourceBuffer.appendBuffer(data)
# }
# */
