defmodule Rtc.Env do
  def init() do
    :persistent_term.put(:hls_dir, Application.fetch_env!(:rtc, :hls)[:hls_dir])
    :persistent_term.put(:dash_dir, Application.fetch_env!(:rtc, :hls)[:dash_dir])
    :persistent_term.put(:ffmpeg, Application.fetch_env!(:rtc, :ffmpeg))
    :persistent_term.put(:fps, Application.get_env(:rtc, :fps))

    :persistent_term.put(
      :haar,
      Path.join([
        :code.priv_dir(:evision),
        "share/opencv4/haarcascades/haarcascade_frontalface_default.xml"
      ])
    )

    models_dir = Application.app_dir(:rtc, "priv/models/")
    :persistent_term.put(:models_dir, models_dir)

    :persistent_term.put(
      :face,
      Path.join(models_dir, Application.get_env(:rtc, :models)[:face_api])
    )
  end

  def hls_dir, do: :persistent_term.get(:hls_dir)
  def dash_dir, do: :persistent_term.get(:dash_dir)
  def ffmpeg, do: :persistent_term.get(:ffmpeg)
  def fps, do: :persistent_term.get(:fps)
  def haar, do: :persistent_term.get(:haar)
  def face, do: :persistent_term.get(:face)
  def models_dir, do: :persistent_term.get(:models_dir)
end
