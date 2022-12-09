defmodule Trace do
  @moduledoc """
  Documentation for `Trace`.
  """

  defmacro calls(ast, max, opts \\ []) do
    case Trace.Spec.parse_ast(ast, __CALLER__) do
      {:ok, spec} ->
        quote do
          Trace.trace(unquote(List.wrap(Macro.escape(spec))), unquote(max), unquote(opts))
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # defmacro calls(ast, max, opts \\ []) do
  #   case Trace.Spec.parse_ast(ast, __CALLER__) do
  #     {:ok, spec} ->
  #       quote do
  #         Trace.trace(List.wrap(unquote(spec)), unquote(max), unquote(opts))
  #       end

  #     {:error, reason} ->
  #       {:error, reason}
  #   end
  # end

  def trace(spec, max, opts) do
    [spec: spec, max: max, opts: opts]
  end
end
