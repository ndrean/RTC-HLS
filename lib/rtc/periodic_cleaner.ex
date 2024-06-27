defmodule Rtc.PeriodicCleaner do
  @moduledoc """
  Runner of the FileCleaner process
  """
  use Task

  def start_link(_), do: Task.start_link(&run/0)
  def run, do: Rtc.FileCleaner.run()
end

defmodule Rtc.FileCleaner do
  @moduledoc """
  Recurring cleanup Task of HLS and DASH files
  """

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  defp hls_path(), do: Application.get_env(:rtc, :hls)[:hls_dir]
  defp dash_path(), do: Application.get_env(:rtc, :hls)[:dash_dir]

  def run(), do: GenServer.cast(__MODULE__, :clean)

  def init(opts), do: {:ok, Keyword.get(opts, :every) * 1_000 * 60}

  def handle_cast(:clean, period) do
    Process.send_after(self(), :clean, period)
    {:noreply, period}
  end

  def handle_info(:clean, period) do
    IO.puts("Cleaning.....")

    clean = fn path ->
      case File.ls!(path) do
        [] ->
          :ok

        files ->
          Enum.each(files, &(Path.join([path, &1]) |> File.rm!()))
      end
    end

    [hls_path(), dash_path()] |> Enum.each(&clean.(&1))

    Process.send_after(self(), :clean, period)
    {:noreply, period}
  end
end
