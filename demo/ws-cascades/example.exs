Mix.install([
	{:plug, "~> 1.6"},
	{:bandit, "~> 1.5"},
  	{:websock_adapter, "~> 0.5"},
	{:ex_cmd, "~> 0.12"},
	{:evision, "~> 0.2"},
	# {:ex_vision, "~>0.2"},
	# {:exla, "~> 0.7"}
])
# config: [
#     nx: [default_backend: EXLA.Backend]
#   ])

defmodule Processor do
	# alias ExVision.Classification.MobileNetV3

	def haar do
		haar_path = 
		Path.join(
			:code.priv_dir(:evision),
			"share/opencv4/haarcascades/haarcascade_frontalface_default.xml"
		)
			
		Evision.CascadeClassifier.cascadeClassifier(haar_path)
	end


  def contour(file, model, model2) do
	curr_path = Path.join("in",file)
	#MobileNetV3.batched_run(MyModel, curr_path) |> dbg()

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
			Evision.rectangle(mat, {x, y}, {x + w, y + h}, {0, 255,0}, thickness: 2)
		end)
		
	Evision.imwrite(Path.join("out", file), img)
	:ok = File.rm!(curr_path)
  end
end


defmodule HomeController do
  def index(conn, _p) do
    Plug.Conn.send_file(conn, 200, "./index.html")
  end
end

defmodule Router do
	use Plug.Router

	# @session_options [
	# 	store: :ets, key: "_my_key", signing_salt: "my_salt", table: :session
	# ]

	plug(:match)
  	plug(:dispatch)


	get "/" do
		HomeController.index(conn, %{})
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

	# alias ExVision.Classification.MobileNetV3

	@t 10
	require Logger

	@impl true
	def init(_args) do

		# command to save video into files of frames with ExCmd.Process

		########################################################################################
		
		#  ffmpeg [GeneralOptions] [InputFileOptions] -i input [OutputFileOptions] output

		########################################################################################


		# 1) output at rate 30fps, size 640x480
		#  get_frames = 
       	# 	~w(ffmpeg -loglevel warning  -i pipe:0  -framerate 30 -video_size 640x480 -y in/test_%004d.jpg)
		
		get_frames = 
			~w(ffmpeg -loglevel warning -i pipe:0 -framerate 30 -video_size 640x480 in/test_%04d.jpg)


		# command to rebuild video from frames with ExCmd.Process
		#  fn_rebuild = fn curr_mp4 ->
		#  	~w(ffmpeg -loglevel warning  -f image2pipe  -framerate 30 -i pipe:0 -c:v libx264 -preset slow -crf 22 -y #{curr_mp4})
		#  end

		# 2) input at rate 30fps, size 640x480
		fn_rebuild = fn curr_webm ->
			~w(ffmpeg -loglevel warning -f image2pipe  -framerate 30 -i pipe:0  -c:v libvpx -b:v 1M -f webm -deadline realtime  -y #{curr_webm})
		end

    	{:ok, pid_into_file} = ExCmd.Process.start_link(get_frames, log: true)

		Logger.debug("INITIALIZED------into_file: #{inspect(pid_into_file)}")

		#model2 = MobileNetV3.load() |> dbg()
		state = %{
			model: Processor.haar(),
			model2: nil,
			pid_into_file: pid_into_file, 
			pid_rebuild: nil,
			fn_rebuild: fn_rebuild,
			queue: :queue.new(),
			processed: [],
			webm: nil,
			ref: nil,
			i: 1
		}

		{:ok, state}
	end

	@impl true
	def handle_in({"stop", [opcode: :text]}, state) do
		Logger.warning("STOPPED------")
		File.ls!("in") |> Enum.each(&File.rm!(Path.join("in", &1)))
		:ok = gracefully_stop(state.pid_into_file)
		:ok = gracefully_stop(state.pid_rebuild)
		{:stop, :normal, state}
	end

	def handle_in({msg, [opcode: :binary]}, state) do
		Logger.debug("received data ---------------")
		:ok = ExCmd.Process.write(state.pid_into_file, msg)
		send(self(), :ffmpeg_processed)
		{:ok, state}
	end

	@impl true
	def handle_info({:EXIT, pid, reason}, state) do
		Logger.debug("EXITED: #{inspect(pid)}: #{inspect(reason)}")
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
		%{queue: queue, model: model, model2: model2} = state
		case :queue.out(queue) do
			{{:value, files}, new_queue}  ->
				Task.async_stream(files, fn file -> 
					Processor.contour(file, model, model2)
				end)
				|> Stream.run()
				send(self(), :process_queue)
				{:ok,%{state | queue: new_queue, processed: files}}
		
			{:empty, _} ->
				send(self(), :ffmpeg_rebuild)
				{:ok, state}
		end
	end

	# initial rebuild
	def handle_info(:ffmpeg_rebuild, %{pid_rebuild: nil} = state) do
		%{
			fn_rebuild: fn_rebuild,
			processed: processed, 
			i: i, 
		} = state

		timestamp = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
		webm = "out/out_#{timestamp}.webm"
				
		{:ok, pid_rebuild} = 
			ExCmd.Process.start_link(fn_rebuild.(webm), log: true)
					
		process(pid_rebuild, processed)

		{:ok, %{
			state | 
				pid_rebuild: pid_rebuild, 
				processed: [],
				webm: webm,
				i: i+1, 
			}
		}
	end

	#  every 5th chunk we send to the browser
	def handle_info(:ffmpeg_rebuild, %{i: i} = state) when rem(i, @t) == 1 do
		%{
			pid_rebuild: pid_rebuild, 
			fn_rebuild: fn_rebuild, 
			processed: processed,
			webm: webm,
			i: i, 
			} = state
		
		Logger.debug("Stopping rebuild process...#{inspect(pid_rebuild)}")

		%{ref: ref} = 
			Task.async(fn -> 
				:ok = gracefully_stop(pid_rebuild) 
				webm
			end)
		
		timestamp = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
		new_webm = "out/out_#{timestamp}.webm"
		{:ok, new_pid_rebuild} = 
			ExCmd.Process.start_link(fn_rebuild.(new_webm))
			
		process(new_pid_rebuild, processed)

		{:ok,
			%{state | 
				pid_rebuild: new_pid_rebuild, 
				processed: [], 
				webm: new_webm,
				ref: ref,
				i: i+1, 
			}
		}
	end

	def handle_info(:ffmpeg_rebuild, state) do
		%{
			pid_rebuild: pid_rebuild, 
			processed: processed, 
			i: i
		} = state

		process(pid_rebuild, processed)
		
		{:ok, %{state | processed: [], i: i+1}}
	end

	# return from Task.async
	def handle_info({ref, webm}, %{ref: ref} = state) do
		send(self(), {:send_to_browser, webm})
		{:ok, %{state | ref: nil}}
	end

	def handle_info({:DOWN,_, :process, _, :normal}, state) do
		{:ok, state}
	end

	def handle_info({:send_to_browser, webm}, state) do
		data = File.read!(webm)
		Logger.debug("SENDING TO BROWSER...#{webm}, #{byte_size(data)}")
		{:push, {:binary, data}, state}
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
			ExCmd.Process.await_exit(pid, 500)
			ExCmd.Process.stop(pid)
		end
		:ok
	end

	defp process(pid, processed) do
		processed = Enum.sort(processed)
		for file <- processed do
			ExCmd.Process.write(pid, File.read!(Path.join("out", file)))
		end
		Enum.each(processed, &File.rm(Path.join("out", &1)))
	end
end

webserver = {Bandit, plug: Router, port: 4000}
{:ok, _} = Supervisor.start_link([webserver], strategy: :one_for_one)
Process.sleep(:infinity)

