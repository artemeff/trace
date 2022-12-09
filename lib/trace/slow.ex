defmodule Trace.Slow do
  defmodule Formatter do
    def format(calls) do
      calls
      |> Enum.map(fn({pid, trace}) -> {pid, drop_trash(trace)} end)
      |> Enum.map(fn({pid, trace}) -> {pid, calculate_total(trace), trace} end)
      |> Enum.sort_by(fn({_, total, _}) -> total end, :desc)
      |> Enum.each(fn({pid, total, trace}) ->
           IO.puts([inspect(pid), " ", format_time(total)])
           format_trace(trace)
           IO.puts("")
         end)
    end

    defp format_trace([]) do
      :ok
    end

    defp format_trace([{_, _, [{m, f, _}|_]}|_] = trace) do
      trace_end_idx = Enum.find_index(trace, fn
        ({:return_from, _, [{^m, ^f, _}|_]}) -> true
        (_) -> false
      end)

      trace_captured = Enum.take(trace, trace_end_idx + 1)
      trace_idx = Enum.with_index(trace_captured)

      Enum.reduce_while(trace_idx, 0, fn({{type, time, call}, index}, level) ->
        case type do
          :call ->
            case find_return(call, index, trace) do
              {:return_from, time_return, [_, return]} ->
                IO.puts([
                  pad_level(level),
                  ?\s, ?\s,
                  ?+,
                  String.pad_leading(format_time_diff(time, time_return), 11),
                  ?\s,
                  format_call(type, call),
                  " -> ", inspect(return)
                ])

                {:cont, level + 1}

              nil ->
                {:halt, level}
            end

          :return_from ->
            {:cont, max(level - 1, 0)}
        end
      end)
    end

    defp calculate_total([a|_] = trace) do
      time_start = elem(a, 1)
      time_end = elem(List.last(trace), 1)

      time_end - time_start
    end

    defp calculate_total(_) do
      0
    end

    defp drop_trash([]) do
      []
    end

    defp drop_trash([{_, _, [{m, f, _}|_]}|_] = trace) do
      trace_end_idx = Enum.find_index(trace, fn
        ({:return_from, _, [{^m, ^f, _}|_]}) -> true
        (_) -> false
      end)

      Enum.take(trace, trace_end_idx + 1)
    end

    defp find_return([{m, f, _}], idx, trace) do
      trace
      |> Enum.drop(idx)
      |> Enum.find(fn
           ({:return_from, _, [{^m, ^f, _}, _]}) -> true
           (_) -> false
         end)
    end

    defp pad_level(level) do
      String.pad_leading("", level * 2, [" "])
    end

    defp format_time_diff(time0, time1) do
      format_time(time1 - time0)
    end

    defp format_time(native) do
      :erlang.float_to_binary(native / 1000, decimals: 3) <> "ms"
    end

    defp format_call(:call, [{m, f, a}]) do
      args =
        a
        |> Enum.map(&inspect/1)
        |> Enum.join(", ")

      [inspect(m), ".", to_string(f), "(",  args, ")"]
    end

    defp format_call(:return_from, [{m, f, a}, return]) do
      [inspect(m), ".", to_string(f), "/", to_string(a), " -> ", inspect(return)]
    end
  end

  defmodule Collector do
    use GenServer

    defmodule State do
      defstruct [
        process_after: :timer.seconds(5),
        captured_pids: MapSet.new(),
        captured: nil,
        calls_max: 0,
        calls_done: 0,
        calls: %{},
        block: nil,
        notifier: nil
      ]
    end

    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, opts)
    end

    def init(opts) do
      {:ok, %State{
        process_after: Keyword.get(opts, :process_after, :timer.seconds(5)),
        calls_max: Keyword.get(opts, :max, 0),
        block: Keyword.fetch!(opts, :block),
        notifier: Keyword.get(opts, :notifier)
      }}
    end

    def handle_continue(:format, %State{} = state) do
      Trace.Slow.clear()

      calls = Enum.reduce(state.calls, [], fn({pid, calls}, acc) ->
        acc ++ Enum.map(calls, &({pid, &1}))
      end)

      notify(state, calls)
      Formatter.format(calls)

      {:stop, :normal, state}
    end

    def handle_info(:timeout, %State{} = state) do
      {:noreply, state, {:continue, :format}}
    end

    def handle_info({:trace_ts, pid, :call, {m, f, _}, _} = block, %State{block: {m, f}} = state) do
      state = %State{state|captured_pids: MapSet.put(state.captured_pids, pid)}

      {:noreply, put_block(state, block)}
    end

    def handle_info(block, %State{} = state) do
      if MapSet.member?(state.captured_pids, elem(block, 1)) do
        state = put_block(state, block)

        if state.calls_done >= state.calls_max do
          {:noreply, state, {:continue, :format}}
        else
          {:noreply, state, state.process_after}
        end
      else
        {:noreply, state}
      end
    end

    defp put_block(%State{block: {block_m, block_f}} = state, block) do
      case block do
        {:trace_ts, pid, :call, {^block_m, ^block_f, _} = mfa, time} ->
          call = {:call, timestamp(time), [mfa]}
          calls_pid = magic(call, [[]|Map.get(state.calls, pid, [])])
          calls = Map.put(state.calls, pid, calls_pid)

          %State{state|calls: calls, captured: pid}

        {:trace_ts, pid, :return_from, {^block_m, ^block_f, _} = mfa, return, time} ->
          call = {:return_from, timestamp(time), [mfa, return]}
          calls_pid = magic(call, Map.get(state.calls, pid, []))
          calls = Map.put(state.calls, pid, calls_pid)

          %State{state|calls: calls, calls_done: state.calls_done + 1, captured: nil}

        {:trace_ts, pid, :call, mfa, time} ->
          call = {:call, timestamp(time), [mfa]}
          calls_pid = magic(call, Map.get(state.calls, pid, []))
          calls = Map.put(state.calls, pid, calls_pid)

          %State{state|calls: calls}

        {:trace_ts, pid, :return_from, mfa, return, time} ->
          call = {:return_from, timestamp(time), [mfa, return]}
          calls_pid = magic(call, Map.get(state.calls, pid, []))
          calls = Map.put(state.calls, pid, calls_pid)

          %State{state|calls: calls}
      end
    end

    defp magic(term, [head|tail]) do
      [head ++ [term]|tail]
    end

    defp timestamp({mega, sec, micro}) do
      mega * 1000000 * 1000000 + sec * 1000000 + micro
    end

    defp notify(%State{notifier: pid}, term) when is_pid(pid) do
      send(pid, {__MODULE__, term})
    end

    defp notify(%State{}, _) do
      :ok
    end
  end

  def calls(spec, max, opts \\ [])

  def calls({_, _, _} = spec, max, opts) do
    calls([spec], max, opts)
  end

  def calls(specs, max, opts) do
    with {:ok, pid} <- Collector.start_link(collector_opts(specs, max, opts)) do
      trace(pid, specs, opts)
    end
  end

  @spec mf_all(module(), atom(), pos_integer(), Keyword.t()) :: :ok
  def mf_all(module, function, max, opts) do
    calls([
      {module, function, :_}, {:_, :_, :_}
    ], max, opts)
  end

  @spec mf_pid(module(), atom(), pid(), pos_integer(), Keyword.t()) :: :ok
  def mf_pid(module, function, pid, max, opts) do
    calls([
      {module, function, :_}, {:_, :_, :_}
    ], max, Keyword.put(opts, :pid, pid))
  end

  @spec mf_prefix(module(), atom(), module() | atom(), pos_integer(), Keyword.t()) :: :ok
  def mf_prefix(module, function, application, max, opts) do
    specs =
      Enum.reduce(:erlang.loaded(), [], fn(mod, acc) ->
        if String.starts_with?(Atom.to_string(mod), Atom.to_string(application)) do
          [{mod, :_, :_}|acc]
        else
          acc
        end
      end)

    calls([
      {module, function, :_} | specs
    ], max, opts)
  end

  def clear do
    :erlang.trace(:all, false, [:all])
    :erlang.trace_pattern({:_, :_, :_}, false, [:local, :meta, :call_count, :call_time])
    :erlang.trace_pattern({:_, :_, :_}, false, []) # unsets global
  end

  defp trace(pid, specs, opts) do
    matches = Enum.map(specs, fn(spec) ->
      :erlang.trace_pattern(spec, [{:_, [], [{:return_trace}]}], [:global])
    end)

    for spec <- pid_specs(Keyword.get(opts, :pid, :all)) do
      :erlang.trace(spec, true, [:call, {:tracer, pid}, :timestamp])
    end

    Enum.sum(matches)
  end

  defp pid_specs(term) when is_list(term) do
    Enum.flat_map(term, &pid_specs/1)
  end

  defp pid_specs(term) when term in [:all, :existing, :new] do
    [term]
  end

  defp pid_specs(term) when is_pid(term) or is_port(term) do
    [term]
  end

  defp collector_opts(specs, max, opts) do
    opts
    |> Keyword.put_new_lazy(:block, fn ->
         {m, f, _} = List.first(specs)
         {m, f}
       end)
    |> Keyword.put(:max, max)
  end
end
