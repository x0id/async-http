defmodule AsyncHttp.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [AsyncHttp.Worker]
    opts = [strategy: :one_for_one, name: AsyncHttp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
