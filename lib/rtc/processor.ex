defmodule Rtc.ProcessorAgent do
  use Agent

  alias Evision.CascadeClassifier
  alias Rtc.Env

  @moduledoc """
  Agent to load and hold the Haar Cascade model for the processor.
  """

  def start_link(type: type, user_id: user_id) do
    # face_cascade_path =
    #   Path.join([Env.haar(), "haarcascade_frontalface_default.xml"])
    #   |> dbg()

    face_cascade_path = Env.haar()

    face_cascade_model = CascadeClassifier.cascadeClassifier(face_cascade_path) |> dbg()

    state = %{type: type, user_id: user_id, face_cascade_model: face_cascade_model}
    Agent.start_link(fn -> state end, name: __MODULE__)
  end

  def get_haar_model do
    Agent.get(__MODULE__, fn state -> state.face_cascade_model end)
  end
end

defmodule Rtc.Processor do
  @moduledoc """
  Processes HLS segments, detects faces in 1 out of every 20 frames,
  and adds a rectangle around detected faces.
  """
  alias Evision.{CascadeClassifier, VideoCapture, Constant}
  alias Evision, as: Cv

  def process_video do
    IO.puts("EVISION Process------")
    capture = VideoCapture.videoCapture(0) |> dbg()

    frame = VideoCapture.read(capture) |> dbg()
    # %{shape: {h,w,ch}}= frame
    # frame = Cv.resize(frame, {w, h}) |> dbg()
    grey_frame = Cv.cvtColor(frame, Constant.cv_COLOR_BGR2GRAY())
    dbg(grey_frame)
    detect_and_redraw(grey_frame)
  end

  def detect_and_redraw(grey_frame) do
    face_cascade_model = Rtc.ProcessorAgent.get_haar_model()

    faces =
      CascadeClassifier.detectMultiScale(face_cascade_model, grey_frame,
        scaleFactor: 1.8,
        minNeighbors: 1
      )
      |> dbg()

    Enum.reduce(faces, grey_frame, fn {x, y, w, h}, mat ->
      Cv.rectangle(mat, {x, y}, {x + w, y + h}, {0, 0, 255}, thickness: 2)
    end)
  end

  def process_frame(frame_binary, output_path) do
    # frame_binary
    # |> Mat.from_binary(frame_binary, Cv.Constant.cv_IMPREAD_COLOR())
    # |> detect_and_redraw()
    # |> save_frame(0, output_path)
  end

  def process_segment(segment_path, output_path) do
    every = Application.get_env(:rtc, :hls)[:every]

    capture =
      VideoCapture.videoCapture(segment_path)

    for i <- 0..(capture.frame_count - 1) do
      # Grabs, decodes and returns the next video frame.
      frame_at_i = VideoCapture.read(capture)

      if rem(i, every) == 0 do
        detect_and_redraw(frame_at_i)
      else
        frame_at_i
      end
      |> save_frame(i, output_path)
    end
  end

  def save_frame(frame, index, output_path) do
    Path.join(output_path, "frame_#{index}.jpg")
    # Saves an image to a specified file.
    |> Evision.imwrite(frame)
  end

  def reassemble_segment(output_path, original_file_path) do
    ffmpeg = Application.fetch_env!(:rtc, :ffmpeg)
    mp4_path = Path.join(output_path, "output_segment.mp4")
    ts_path = Path.join(output_path, "output_segment.ts")

    # Convert images to video
    System.cmd(ffmpeg, [
      "-framerate",
      "30",
      "-i",
      "#{output_path}/frame_%d.jpg",
      "-c:v",
      "libx264",
      "-pix_fmt",
      "yuv420p",
      "-profile:v",
      "baseline",
      "-level",
      "3.0",
      mp4_path
    ])

    # Convert MP4 to TS segment
    System.cmd(ffmpeg, [
      "-i",
      mp4_path,
      "-c",
      "copy",
      "-bsf:v",
      "h264_mp4toannexb",
      "-f",
      "mpegts",
      ts_path
    ])

    # Replace the original file with the processed one (if needed)
    File.rename(ts_path, original_file_path)
  end
end
