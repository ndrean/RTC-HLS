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
		input_path = Path.join("priv/input",file)
		output_path = Path.join("priv/output",file)

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

defmodule FFmpegProcessor do
	def start(frame_rate, resolution, duration) do
		frame_pattern =  "priv/input/test_%05d.jpg"
		build_frames =
			~w(ffmpeg -loglevel debug -i pipe:0 -framerate #{frame_rate} -video_size #{resolution} -thread_type slice #{frame_pattern})
		
		{:ok, pid_capture} = 
			ExCmd.Process.start_link(build_frames)

		playlist = Path.join("priv/hls", "playlist.m3u8")
		segment = Path.join("priv/hls", "segment_%03d.ts")

		ffmpeg_rebuild_cmd = ~w(
			ffmpeg -loglevel info -f image2pipe -framerate #{frame_rate} -i pipe:0 
			-c:v libx264 -preset veryfast 
			-f hls 
			-hls_time #{duration} 
			-hls_list_size 4 
			-hls_playlist_type event
			-hls_flags append_list 
			-hls_segment_filename #{segment} 
			#{playlist}
		)
			# w(ffmpeg -loglevel warning  -i pipe:0  -framerate 30 -video_size 640x480 -y in/test_%004d.jpg)
	
		{:ok, pid_segment} = 
			ExCmd.Process.start_link(ffmpeg_rebuild_cmd)

		{pid_capture, pid_segment}
	end
end

##################################################################################
# ffmpeg [GeneralOptions] [InputFileOptions] -i input [OutputFileOptions] output #
##################################################################################

# defmodule VideoSegmenter do
#   require Logger

# 	def create_video_chunk(frame_files, frame_rate) do
#     Logger.debug("FFmpeg_rebuild ----#{ length(frame_files)}")

# 		timestamp = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
# 		segment = Path.join("priv/output", "out_#{timestamp}.webm")
# 		ffmpeg_rebuild_cmd = 
# 			~w(ffmpeg -loglevel info -f image2pipe  -framerate #{frame_rate} -i pipe:0  -c:v libvpx -b:v 1M -f webm -deadline realtime  -y #{segment})
      
#       # version mp4 not working???
#     	# ~w(ffmpeg -loglevel warning  -f image2pipe  -framerate 30 -i pipe:0 -c:v libx264 -preset slow -crf 22 -y #{curr_mp4})

#       {:ok, pid} = 
#         ExCmd.Process.start_link(ffmpeg_rebuild_cmd, log: true)
        
#     for file <- frame_files do
#       :ok = ExCmd.Process.write(pid, File.read!(Path.join("priv/output", file)))
#     end
#     :ok = ExCmd.Process.close_stdin(pid)
#     ExCmd.Process.await_exit(pid, 100)
    
#     # :ok = Enum.each(frame_files, &File.rm(Path.join("output", &1)))
#     segment
# 	end

	# def create_video_segment_and_playlist(pid, frame_files, frame_rate) do
  #   Logger.debug("FFmpeg_rebuild ----#{length(frame_files)}")
    
  #   #timestamp = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
  #   # segment = Path.join("priv/hls", "segment_%03d.ts")
  #   # playlist = Path.join("priv/hls", "playlist.m3u8")


  #   # ffmpeg_rebuild_cmd = ~w(
  #   #   ffmpeg -loglevel info -f image2pipe -framerate #{frame_rate} -i pipe:0 
  #   #   -c:v libx264 -preset veryfast 
	# 	# 	-f hls 
	# 	# 	-hls_time 5 
	# 	# 	-hls_list_size 4 
	# 	# 	-hls_flags append_list 
	# 	# 	-hls_segment_filename #{segment} 
	# 	# 	#{playlist}
  #   # )

  #   # {:ok, pid} = ExCmd.Process.start_link(ffmpeg_rebuild_cmd)

  #   for file <- frame_files do
  #     :ok = ExCmd.Process.write(pid, File.read!(Path.join("priv/output", file)))
  #   end

  #   # :ok = ExCmd.Process.close_stdin(pid)
  #   # ExCmd.Process.await_exit(pid, 100)

  #   :ok = Enum.each(frame_files, &File.rm(Path.join("priv/output", &1)))

  #   playlist
#   end
# end
