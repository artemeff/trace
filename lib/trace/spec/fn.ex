defmodule Trace.Spec.Fn do
  defmacro to_match_spec(ast) do
    quote do
      unquote(to_spec(ast, __CALLER__))
    end
  end

  defp to_spec(ast, env) do
    {ast, variables} = prewalk_variables(ast, env)

    ast
    |> decompose_fn()
    |> Enum.map(&(compile(variables, &1, env)))
  end

  # we have a problem, we should handle var in args and guards in separate ways
  # because in args we should provide binding like `^var`, but in guards we should use `var`
  #
  # iex> var = 42
  #
  # it should use a :"$1" here:
  #
  # iex> to_match_spec fn(var) -> :ok end
  # [{[42], [], [:ok]}]
  #
  # and this case is ok:
  #
  # iex> to_match_spec fn(a) when a == var -> :ok end
  # [{:"$1", {:==, :"$1", {:const, 42}}, [:ok]}]
  defp prewalk_variables(ast, env) do
    Macro.prewalk(ast, %{}, fn
      # bindings
      ({:^, _, [{var, _, nil} = ast]}, acc) when is_atom(var) ->
        {{var, [], nil}, prewalk_variables_append(ast, env, acc)}

      # variables
      ({var, _, nil} = ast, acc) when is_atom(var) ->
        {ast, prewalk_variables_append(ast, env, acc)}

      (ast, acc) ->
        {ast, acc}
    end)
  end

  defp prewalk_variables_append({:_, _, _}, _, acc) do
    acc
  end

  defp prewalk_variables_append({var, _, nil} = ast, env, acc) do
    if Map.has_key?(acc, var) do
      acc
    else
      index_atom = Map.get_lazy(acc, var, fn -> :"$#{map_size(acc) + 1}" end)

      if Macro.Env.has_var?(env, {var, nil}) do
        Map.put(acc, var, {:const, ast})
      else
        Map.put(acc, var, index_atom)
      end
    end
  end

  defp decompose_fn({:fn, _, bodies}) do
    Enum.map(bodies, &decompose_fn_body/1)
  end

  defp decompose_fn_body({:->, _, [args, return]}) do
    # IO.inspect(args)

    case decompose_fn_args(args) do
      {[], args} ->
        {args, [], return}

      {args, guards} ->
        {args, guards, return}
    end
  end

  defp decompose_fn_args([{:when, _, [args, guards]}]) do
    {args, guards}
  end

  defp decompose_fn_args([{:when, _, ast}]) do
    decompose_fn_args(ast)
  end

  defp decompose_fn_args(ast) do
    Enum.split_with(ast, fn
      ({_, _, nil}) -> true
      (_) -> false
    end)
  end

  defp compile(variables, {args, guards, return}, _env) do
    IO.inspect(variables, label: "variables")
    IO.inspect(args, label: "args")
    IO.inspect(guards, label: "guards")
    IO.inspect(return, label: "return")

    # args_ast =
    #   Enum.red(args, fn
    #     ({:_, _, _}) ->

    #     ({var, _, _}) ->
    #       case Map.fetch(variables, var) do
    #         {:ok, {:const, term}} -> term
    #         {:ok, term} -> term
    #         :error -> raise "what"
    #       end
    #   end)

    args_ast = compile_args(args, variables)

    IO.inspect(args, label: "args")
    IO.inspect(args_ast, label: "args_ast")
    IO.puts(Macro.to_string(args_ast))

    guards_ast = compile_guards(guards, variables)

    # IO.inspect(guards, label: "guards")
    # IO.inspect(guards_ast, label: "guards_ast")
    # IO.puts(Macro.to_string(guards_ast))

    return_ast = compile_return(return, variables)

    # IO.inspect(return, label: "return")
    # IO.inspect(return_ast, label: "return_ast")
    # IO.puts(Macro.to_string(return_ast))

    {:{}, [], [args_ast, guards_ast, [return_ast]]}
  end

  # special case, means - anything
  # fn(_) -> ... end
  # defp compile_args([{:_, _, _}], _variables) do
  #   :_
  # end

  # tuple args - fallback for ets match spec
  # fn({_, _}) -> ... end
  # defp compile_args([{:{}, meta, args}], variables) do
  #   {:{}, meta, compile_args(args, variables)}
  # end

  # defp compile_args([args], variables) when is_tuple(args) do
  #   args
  #   |> :erlang.tuple_to_list()
  #   |> compile_args(variables)
  #   |> :erlang.list_to_tuple()
  # end

  # list args - fallback for dbg match spec
  # fn([_, _]) -> ... end
  # defp compile_args([args], variables) when is_list(args) do
  #   compile_args(args, variables)
  # end

  # elixir-style args - fits dbg match spec
  # fn(_, _) -> ... end
  defp compile_args(args, variables) do
    # for {var, _, _} <- args do
    #   case Map.fetch(variables, var) do
    #     {:ok, {:const, term}} -> term
    #     {:ok, term} -> term
    #     :error -> :_
    #   end
    # end

    Macro.postwalk(args, fn
      ({var, _, nil}) ->
        case Map.fetch(variables, var) do
          {:ok, {:const, term}} -> term
          {:ok, term} -> term
          :error -> :_
        end

      (ast) ->
        ast
    end)
  end

  # semicolon `;` signifies a boolean OR
  # and comma `,` signifies a boolean AND
  #
  # > ets:fun2ms(fun(A) when A > 0; A < 10 -> ok end).
  # [{'$1',[{'>','$1',0}],[ok]},{'$1',[{'<','$1',10}],[ok]}]
  # > ets:fun2ms(fun(A) when A > 0 orelse A < 10 -> ok end).
  # [{'$1',[{'orelse',{'>','$1',0},{'<','$1',10}}],[ok]}]
  #
  # > ets:fun2ms(fun(A) when A > 0, A < 10 -> ok end).
  # [{'$1',[{'>','$1',0},{'<','$1',10}],[ok]}]
  # > ets:fun2ms(fun(A) when A > 0 andalso A < 10 -> ok end).
  # [{'$1',[{'andalso',{'>','$1',0},{'<','$1',10}}],[ok]}]
  defp compile_guards(guards, variables) do
    Macro.postwalk(guards, fn
      ({var, _, nil} = ast) when is_atom(var) ->
        case Map.fetch(variables, var) do
          {:ok, term} ->
            term

          :error ->
            ast
        end

      # ({comp, _, [_, _] = args} = ast) when comp in [:+, :-, :*, :/] ->
      #   const? =
      #     Enum.all?(args, fn
      #       ({:const, _}) -> true
      #       (var) when is_atom(var) -> false
      #       (_) -> true
      #     end)

      #   if const? do
      #     {comp, [], Enum.map(args, fn
      #       ({:const, t}) -> t
      #       (t) -> t
      #     end)}
      #   else
      #     ast
      #   end

      ({guard, _, [_|_] = args}) ->
        quote do
          {unquote(guard_name(guard)), unquote_splicing(args)}
        end

      (ast) ->
        ast
    end)
  end

  defp compile_return(return, variables) do
    Macro.postwalk(return, fn
      ({var, _, nil} = ast) when is_atom(var) ->
        case Map.fetch(variables, var) do
          {:ok, term} ->
            term

          :error ->
            ast
        end

      ({guard, _, [_|_] = args}) ->
        quote do
          {unquote(guard_name(guard)), unquote_splicing(args)}
        end

      (ast) ->
        ast
    end)
  end

  defp guard_name(:and) do
    :andalso
  end

  defp guard_name(:or) do
    :orelse
  end

  defp guard_name(term) do
    term
  end
end
