defmodule App do
  use Application

  def start(_,_) do
    webserver = {Bandit, plug: WebRouter, port: 4000}
    Supervisor.start_link([webserver], strategy: :one_for_one)
  end
end