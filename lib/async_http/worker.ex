require Logger

defmodule AsyncHttp.Worker do
  use GenServer
  use TypedStruct

  typedstruct module: State do
    field :async_states, map
  end

  def child_spec(_) do
    %{id: __MODULE__, start: {GenServer, :start_link, [__MODULE__, [], [name: __MODULE__]]}}
  end

  @impl true
  def init(_) do
    IO.puts("started...")
    state = %State{async_states: SplitStates.Container.new()}
    {:ok, state}
  end

  @impl true
  def handle_call({:cast, target, event}, _from, state) do
    update_in(state.async_states, &SplitStates.init(&1, target, event))
    |> reply(:ok)
  end

  def handle_call({:call, target, event}, from, state) do
    caller = {:callback, &GenServer.reply(from, &1)}

    update_in(state.async_states, &SplitStates.init(&1, target, event, caller))
    |> noreply()
  end

  @impl true
  # sent by BlockingOp
  def handle_info({:result, target, result}, state) do
    update_in(state.async_states, &SplitStates.handle(&1, target, [:result, result]))
    |> noreply()
  end

  # sent by BlockingOp
  def handle_info({{:DOWN, target}, _mref, :process, _pid, reason}, state) do
    update_in(state.async_states, &SplitStates.handle(&1, target, [:exit, reason]))
    |> noreply()
  end

  # sent by BlockingOp
  def handle_info({:timeout, target}, state) do
    update_in(state.async_states, &SplitStates.handle(&1, target, [:timeout]))
    |> noreply()
  end

  # handle gen_tcp/ssl closed message
  def handle_info({tag, socket}, state) when tag in [:tcp_closed, :ssl_closed] do
    state |> handle_conn(socket, [:closed]) |> noreply()
  end

  # handle gen_tcp/ssl error message
  def handle_info({tag, socket, reason}, state) when tag in [:tcp_error, :ssl_error] do
    state |> handle_conn(socket, [:error, reason]) |> noreply()
  end

  # handle gen_tcp/ssl data message
  def handle_info({tag, socket, _data} = message, state) when tag in [:tcp, :ssl] do
    state |> handle_conn(socket, [:message, message]) |> noreply()
  end

  def handle_info(msg, state) do
    Logger.warning("unexpected message: #{inspect(msg)}")
    noreply(state)
  end

  defp handle_conn(state, socket, event) do
    case Process.get({:ep, socket}) do
      nil ->
        state

      server ->
        target = {AsyncHttp.Conn, server}
        update_in(state.async_states, &SplitStates.handle(&1, target, event))
    end
  end

  defp reply(state, result), do: {:reply, result, state}

  defp noreply(state), do: {:noreply, state}
end
