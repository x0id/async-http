require Logger

defmodule AsyncHttp.Conn do
  defstruct [:ep, :conn, reqs: %{}]

  def init({__MODULE__, server}, ms) do
    target = {AsyncHttp.BlockingOp, make_ref()}

    op = fn ->
      with {:ok, conn} <- connect(server),
           worker <- Process.whereis(AsyncHttp.Worker),
           {:ok, conn} <- Mint.HTTP.controlling_process(conn, worker) do
        Logger.debug("connection established")
        {:ok, conn}
      end
    end

    state = %__MODULE__{ep: server}
    [{:set, state}, {:call, target, [op, ms], :connect_result}]
  end

  def serve(%__MODULE__{conn: nil}, _), do: :idle
  def serve(%__MODULE__{conn: conn}, _), do: {:return, {:ok, conn}}

  def handle(_state, :closed) do
    Logger.debug("socket closed")
    {:stop, :closed}
  end

  def handle(_, :connect_result, :timeout), do: {:stop, {:error, :timeout}}
  def handle(_, :connect_result, {:exit, reason}), do: {:stop, {:error, {:exit, reason}}}

  def handle(state, :connect_result, {:result, {:ok, conn} = result}) do
    state = state |> register_connection(conn)
    [{:set, state}, {:return, result}]
  end

  def handle(_state, :connect_result, {:result, error}) do
    Logger.error("connection error: #{inspect(error)}")
    {:stop, error}
  end

  def handle(_state, :error, reason) do
    Logger.error("socket error: #{inspect(reason)}")
    {:stop, reason}
  end

  # remove request
  def handle(%__MODULE__{reqs: reqs} = state, :del_req, request_ref) do
    {:set, %__MODULE__{state | reqs: Map.delete(reqs, request_ref)}}
  end

  def handle(%__MODULE__{conn: conn} = state, :message, message) do
    case Mint.HTTP.stream(conn, message) do
      {:ok, conn, responses} ->
        ret =
          Enum.group_by(responses, fn
            {:status, ref, _} -> ref
            {:headers, ref, _} -> ref
            {:data, ref, _} -> ref
            {:done, ref} -> ref
            {:error, ref, _} -> ref
          end)
          |> Enum.flat_map(fn {ref, x} ->
            case Map.get(state.reqs, ref) do
              nil -> []
              query -> [{:tell, {AsyncHttp.Query, {state.ep, query}}, [:response, x]}]
            end
          end)

        [{:set, %__MODULE__{state | conn: conn}} | ret]

      other ->
        Logger.warning("error message #{inspect(message)}: #{inspect(other)}")
        :idle
    end
  end

  # update connection state, save request
  def handle(%__MODULE__{reqs: reqs} = state, :request, conn, query, request_ref) do
    {:set, %__MODULE__{state | conn: conn, reqs: Map.put(reqs, request_ref, query)}}
  end

  defp connect({scheme, address, port}), do: Mint.HTTP.connect(scheme, address, port)
  defp connect(arg), do: {:error, {:badarg, arg}}

  defp register_connection(%__MODULE__{ep: server} = state, conn) do
    set_ep(conn, server)
    %__MODULE__{state | conn: conn}
  end

  defp set_ep(%Mint.HTTP1{socket: socket}, server), do: Process.put({:ep, socket}, server)
  defp set_ep(%Mint.HTTP2{socket: socket}, server), do: Process.put({:ep, socket}, server)
end
