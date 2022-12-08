defmodule Trace.Spec do
  defstruct [
    env: nil,
    module: :_,
    function: :_,
    arguments: :_,
    guards: nil,
    match_spec: nil,
    return: false,
    error: nil
  ]

  alias __MODULE__, as: S

  defguardp is_module(term) when is_atom(term) or is_tuple(term) and elem(term, 0) == :__aliases__
  defguardp is_func(term) when is_atom(term)

  def parse_string(string, env \\ __ENV__) when is_binary(string) do
    with {:ok, ast} <- Code.string_to_quoted(string) do
      parse_ast(ast, env)
    end
  end

  def parse_ast(ast, env \\ __ENV__)

  def parse_ast(ast, env) when is_list(ast) do
    Enum.reduce_while(ast, {:ok, []}, fn(ast, {:ok, acc}) ->
      case parse_ast(ast, env) do
        {:ok, spec} -> {:cont, {:ok, acc ++ [spec]}}
        {:error, r} -> {:halt, {:error, r}}
      end
    end)
  end

  def parse_ast(ast, env) do
    with {:ok, ast} <- parse_maybe(ast, env),
         {:ok, ast} <- expand_m(ast),
         {:ok, ast} <- expand_ag(ast)
    do
      {:ok, spec(ast)}
    end
  end

  defp spec(%S{return: false, arguments: :_} = acc) do
    {acc.module, acc.function, :_}
  end

  defp spec(%S{} = acc) do
    {acc.module, acc.function, spec_return(acc.match_spec)}
  end

  defp spec_return([{arguments, guards, [:return]}]) do
    [{arguments, guards, [:return_trace]}]
  end

  defp spec_return(match_spec) do
    match_spec
  end

  defp parse_maybe(ast, env) do
    case parse(ast, %S{env: env}) do
      %S{error: nil} = ast ->
        {:ok, ast}

      %S{error: reason} ->
        {:error, reason}
    end
  end

  defp parse({:when, _, [ast, {:"::", _, [guards, return]}]}, %S{} = acc) do
    parse(ast, %S{acc | guards: guards, return: parse_return(return)})
  end

  defp parse({:when, _, [ast, guards]}, %S{} = acc) do
    parse(ast, %S{acc | guards: guards})
  end

  defp parse({:"::", _, [ast, return]}, %S{} = acc) do
    parse(ast, %S{acc | return: parse_return(return)})
  end

  defp parse({:/, _, [ast, arguments]}, %S{} = acc) do
    parse(ast, parse_arguments(arguments, acc))
  end

  defp parse({{:., _, [module, function]}, meta, arguments}, %S{} = acc) when is_module(module) and is_func(function) do
    if Keyword.get(meta, :no_parens) do
      parse(module, %S{acc | function: function})
    else
      parse(module, parse_arguments(arguments, %S{acc | function: function}))
    end
  end

  defp parse({:__aliases__, _, [_|_]} = ast, %S{} = acc) do
    %S{acc | module: ast}
  end

  defp parse({:{}, _, [module, function, arguments]}, %S{} = acc) when is_module(module) and is_func(function) do
    parse_arguments(arguments, %S{acc | module: module, function: function})
  end

  defp parse(ast, %S{} = acc) when is_atom(ast) do
    %S{acc | module: ast}
  end

  defp parse(ast, %S{} = acc) do
    %S{acc|error: "invalid spec: " <> Macro.to_string(ast)}
  end

  defp parse_arguments(ast, %S{} = acc) do
    case parse_arguments(ast) do
      {:ok, arguments} -> %S{acc | arguments: arguments}
      {:error, reason} -> %S{acc | error: reason}
    end
  end

  defp parse_arguments({:fn, _, _} = ast) do
    {:ok, ast}
  end

  defp parse_arguments({:_, _, _}) do
    {:ok, :_}
  end

  defp parse_arguments(:_) do
    {:ok, :_}
  end

  defp parse_arguments(ast) when is_integer(ast) do
    {:ok, Enum.map(1..ast, fn(_) -> {:_, [], nil} end)}
  end

  defp parse_arguments([]) do
    {:ok, :_}
  end

  defp parse_arguments([_|_] = ast) do
    {:ok, ast}
  end

  defp parse_arguments(ast) do
    {:error, "invalid arguments: " <> Macro.to_string(ast)}
  end

  defp parse_return({:return, _, [{name, _, _}]}) do
    name
  end

  defp parse_return({:return, _, _}) do
    true
  end

  defp expand_m(%S{module: {:__aliases__, _, _} = ast} = acc) do
    {:ok, %S{acc|module: Macro.expand(ast, acc.env)}}
  end

  defp expand_m(%S{} = acc) do
    {:ok, acc}
  end

  defp expand_ag(%S{arguments: arguments, guards: guards, return: return} = acc) do
    fun2ms = fun2ms_ast(arguments, guards, return)

    case Code.eval_quoted_with_env(fun2ms, [], acc.env) do
      {{:error, :transform_error}, _, _} ->
        {:error, "fun2ms error: " <> Macro.to_string(arguments)}

      {{:error, reason}, _, _} ->
        {:error, reason}

      {[_|_] = spec, _, _} ->
        {:ok, %S{acc|match_spec: spec}}
    end
  end

  defp expand_ag(%S{} = acc) do
    {:ok, acc}
  end

  defp fun2ms_ast({:fn, _, _} = fun, _, _) do
    quote do
      :dbg.fun2ms(unquote(fun))
    end
  end

  defp fun2ms_ast(arguments, guards, return) when is_list(arguments) and is_tuple(guards) do
    quote do
      :dbg.fun2ms(fn(unquote(arguments)) when unquote(guards) -> unquote(fun2ms_ast_return(return)) end)
    end
  end

  defp fun2ms_ast(arguments, _, return) when is_list(arguments) do
    quote do
      :dbg.fun2ms(fn(unquote(arguments)) -> unquote(fun2ms_ast_return(return)) end)
    end
  end

  defp fun2ms_ast(_, _, return) do
    quote do
      :dbg.fun2ms(fn(_) -> unquote(fun2ms_ast_return(return)) end)
    end
  end

  defp fun2ms_ast_return(true) do
    :return_trace
  end

  # TODO impl
  defp fun2ms_ast_return(:stack) do
    :return_stack
  end

  defp fun2ms_ast_return(_) do
    :ok
  end
end
