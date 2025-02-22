defmodule AsyncHttp.BlockingOp do
  def init({__MODULE__, key} = this, fun, ms) do
    # start blocking operation
    {pid, alias_mon} =
      Process.spawn(
        fn ->
          receive do
            amon ->
              send(amon, {:result, this, fun.()})
          end
        end,
        monitor: [alias: :reply_demonitor, tag: {:DOWN, this}]
      )

    # pass alias/monitor to the operation process
    send(pid, alias_mon)

    # setup timer
    tref = Process.send_after(self(), {:timeout, this}, ms)
    {:set, {key, tref}}
  end

  # fire timer (input for external timer event)
  def handle(_, :timeout) do
    {:stop, :timeout}
  end

  # handle exit
  def handle(state, :exit, reason) do
    # cancel timer
    stop_timer(state)

    # stop and return result
    {:stop, {:exit, reason}}
  end

  # handle result
  def handle(state, :result, result) do
    # cancel timer
    stop_timer(state)

    # stop and return result
    {:stop, {:result, result}}
  end

  defp stop_timer({key, tref}) do
    # cancel timer
    Process.cancel_timer(tref)

    # flash timer event if any
    receive do
      {:timeout, {__MODULE__, ^key}} ->
        :ok
    after
      0 ->
        :ok
    end
  end
end
