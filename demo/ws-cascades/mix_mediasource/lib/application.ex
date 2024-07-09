defmodule App do
  use Application

  def start(_,_) do
    Supervisor.start_link([{Bandit, plug: WebRouter, port: 4000}], strategy: :one_for_one)
  end
end