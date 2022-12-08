defmodule TraceTest do
  use ExUnit.Case
  doctest Trace

  describe "#calls" do
    test "gets value from env" do
      id = 42

      Trace.calls(MyMod.function(%{id: ^id}), 10)
    end
  end
end
