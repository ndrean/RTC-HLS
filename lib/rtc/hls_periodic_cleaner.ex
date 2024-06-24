defmodule Rtc.HlsPeriodicCleaner do
  @moduledoc """
  Runner of the FileCleaner process
  """
  use Task

  def start_link(_), do: Task.start_link(&run/0)
  def run, do: Rtc.FileCleaner.run()
end

defmodule Rtc.FileCleaner do
  @moduledoc """
  Recurring cleanup Task
  """

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  defp path(), do: Application.get_env(:rtc, :hls)[:hls_dir]

  def run(), do: GenServer.cast(__MODULE__, :clean)

  def init(opts) do
    period =
      Keyword.get(opts, :every) * 1_000 * 60

    {:ok, period}
  end

  def handle_cast(:clean, period) do
    Process.send_after(self(), :clean, period)
    {:noreply, period}
  end

  def handle_info(:clean, period) do
    dbg(period)

    case File.ls!(path()) do
      [] ->
        :ok

      files ->
        Enum.each(files, &(Path.join([path(), &1]) |> File.rm!()))
    end

    Process.send_after(self(), :clean, period)
    {:noreply, period}
  end
end
