defmodule Trace.IEx.Parser do
  @moduledoc """
  Custom IEx parser to support Trace macro in iex shell.

  Run the following code to enable it:

      IEx.configure(parser: {Trace.IEx.Parser, :parse, []})

  """

  def parse(input, opts, parser_state) do
    case IEx.Evaluator.parse(input, opts, parser_state) do
      {:ok, {:trace, _meta, [expr, opts]}, buffer} ->
        {:ok, transform(expr, opts), buffer}

      {:ok, {:trace, _meta, [expr]}, buffer} ->
        {:ok, transform(expr, []), buffer}

      return ->
        return
    end
  end

  defp transform(expr, opts) do
    quote do
      require Trace
      Trace.calls(unquote(expr), 100, unquote(opts))
    end
  end
end
