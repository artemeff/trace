defmodule Trace.Spec.FnTest do
  use ExUnit.Case, async: true

  # import ExUnit.CaptureIO
  import Trace.Spec.Fn

  test "1" do
    assert [{:_, [], [:ok]}] ==
      to_match_spec(fn(_) -> :ok end)
  end

  test "2" do
    assert [{[:"$1"], [{:is_integer, :"$1"}], [:ok]}] ==
      to_match_spec(fn(a) when is_integer(a) -> :ok end)
  end

  test "3" do
    a = %{value: 42}

    assert [{[%{value: 42}], [], [:ok]}] ==
      to_match_spec(fn(^a) -> :ok end)
  end

  test "4" do
    a = 42

    assert [{[:"$1"], [{:==, :"$1", {:const, 42}}], [:ok]}] ==
      to_match_spec(fn(b) when b == a -> :ok end)
  end
end
