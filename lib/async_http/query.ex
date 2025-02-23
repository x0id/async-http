defmodule AsyncHttp.Response do
  defstruct [:status, :headers, :body, :error]
end

defmodule AsyncHttp.Query do
  defstruct [:ep, :query, acc: %AsyncHttp.Response{}]

  def init({__MODULE__, {server, query}}, ms) do
    state = %__MODULE__{ep: server, query: query}
    [{:set, state}, {:call, {AsyncHttp.Conn, server}, [ms], :conn}]
  end

  def handle(
        %__MODULE__{ep: server, query: {method, path, headers, body} = query},
        :conn,
        {:ok, conn}
      )
      when conn != nil do
    {:ok, conn, request_ref} = Mint.HTTP.request(conn, method, path, headers, body)
    {:tell, {AsyncHttp.Conn, server}, [:request, conn, query, request_ref]}
  end

  def handle(_state, :conn, error) do
    {:stop, error}
  end

  def handle(state, :response, responses) do
    {result, request_ref} =
      Enum.reduce(responses, {state.acc, nil}, fn
        {:status, _, s}, {acc, ref} ->
          {%AsyncHttp.Response{acc | status: s}, ref}

        {:headers, _, h}, {acc, ref} ->
          {%AsyncHttp.Response{acc | headers: h}, ref}

        {:data, _, b}, {acc, ref} ->
          {Map.update(acc, :body, b, fn
             nil -> b
             x -> x <> b
           end), ref}

        {:error, _, e}, {acc, ref} ->
          {%AsyncHttp.Response{acc | error: e}, ref}

        {:done, ref}, {acc, _} ->
          {acc, ref}
      end)

    case request_ref do
      nil ->
        {:set, %__MODULE__{state | acc: result}}

      _ ->
        [{:tell, {AsyncHttp.Conn, state.ep}, [:del_req, request_ref]}, {:stop, result}]
    end
  end
end
