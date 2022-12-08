defmodule Trace.SpecTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Trace.Spec

  test "Foo.Bar", ctx do
    assert {Foo.Bar, :_, :_} == parse(ctx)
  end

  test ":foo", ctx do
    assert {:foo, :_, :_} == parse(ctx)
  end

  test "Foo.Bar.abc", ctx do
    assert {Foo.Bar, :abc, :_} == parse(ctx)
  end

  test ":foo.bar", ctx do
    assert {:foo, :bar, :_} == parse(ctx)
  end

  test "Foo.Bar.abc/2", ctx do
    assert {Foo.Bar, :abc, [
      {[:_, :_], [], [:ok]}
    ]} == parse(ctx)
  end

  test ":foo.bar/2", ctx do
    assert {:foo, :bar, [
      {[:_, :_], [], [:ok]}
    ]} == parse(ctx)
  end

  test "Foo.Bar.abc/_", ctx do
    assert {Foo.Bar, :abc, :_} == parse(ctx)
  end

  test ":foo.bar/_", ctx do
    assert {:foo, :bar, :_} == parse(ctx)
  end

  test "Foo.Bar.abc(_, _)", ctx do
    assert {Foo.Bar, :abc, [
      {[:_, :_], [], [:ok]}
    ]} == parse(ctx)
  end

  test ":foo.bar(_, _)", ctx do
    assert {:foo, :bar, [
      {[:_, :_], [], [:ok]}
    ]} == parse(ctx)
  end

  test "Foo.Bar :: return", ctx do
    assert {Foo.Bar, :_, [
      {:_, [], [:return_trace]}
    ]} == parse(ctx)
  end

  test ":foo :: return", ctx do
    assert {:foo, :_, [
      {:_, [], [:return_trace]}
    ]} == parse(ctx)
  end

  test "Foo.Bar.abc :: return", ctx do
    assert {Foo.Bar, :abc, [
      {:_, [], [:return_trace]}
    ]} == parse(ctx)
  end

  test ":foo.bar :: return", ctx do
    assert {:foo, :bar, [
      {:_, [], [:return_trace]}
    ]} == parse(ctx)
  end

  test "Foo.Bar.abc :: return(stack)", ctx do
    assert {Foo.Bar, :abc, [
      {:_, [], [:return_stack]}
    ]} == parse(ctx)
  end

  test ":foo.bar :: return(stack)", ctx do
    assert {:foo, :bar, [
      {:_, [], [:return_stack]}
    ]} == parse(ctx)
  end

  test "Foo.Bar.abc(a) when is_integer(a)", ctx do
    assert {Foo.Bar, :abc, [
      {[:"$1"], [{:is_integer, :"$1"}], [:ok]}
    ]} == parse(ctx)
  end

  test ":foo.bar(a) when is_integer(a)", ctx do
    assert {:foo, :bar, [
      {[:"$1"], [{:is_integer, :"$1"}], [:ok]}
    ]} == parse(ctx)
  end

  test "Foo.Bar.abc(a, b) when is_integer(a) or is_binary(b) :: return()", ctx do
    assert {Foo.Bar, :abc, [
      {[:"$1", :"$2"], [{:orelse, {:is_integer, :"$1"}, {:is_binary, :"$2"}}], [:return_trace]}
    ]} == parse(ctx)
  end

  test ":foo.bar(a, b) when is_integer(a) or is_binary(b) :: return()", ctx do
    assert {:foo, :bar, [
      {[:"$1", :"$2"], [{:orelse, {:is_integer, :"$1"}, {:is_binary, :"$2"}}], [:return_trace]}
    ]} == parse(ctx)
  end

  test "Foo.Bar.abc(a, b) when is_integer(a) or is_binary(b) :: return(stack)", ctx do
    assert {Foo.Bar, :abc, [
      {[:"$1", :"$2"], [{:orelse, {:is_integer, :"$1"}, {:is_binary, :"$2"}}], [:return_stack]}
    ]} == parse(ctx)
  end

  test ":foo.bar(a, b) when is_integer(a) or is_binary(b) :: return(stack)", ctx do
    assert {:foo, :bar, [
      {[:"$1", :"$2"], [{:orelse, {:is_integer, :"$1"}, {:is_binary, :"$2"}}], [:return_stack]}
    ]} == parse(ctx)
  end

  test "Foo.Bar.abc(%{a: 1}, <<_::binary>>) :: return(stack)", ctx do
    capture_io(fn ->
      assert {:error, reason} = parse(ctx)
      assert "fun2ms error: [%{a: 1}, <<_::binary>>]" == reason
    end)
  end

  test ":foo.bar(%{a: 1}, <<_::binary>>) :: return(stack)", ctx do
    capture_io(fn ->
      assert {:error, reason} = parse(ctx)
      assert "fun2ms error: [%{a: 1}, <<_::binary>>]" == reason
    end)
  end

  test "Foo.Bar.abc(%{a: a}) when is_integer(a) :: return(stack)", ctx do
    assert {Foo.Bar, :abc, [
      {[%{a: :"$1"}], [{:is_integer, :"$1"}], [:return_stack]}
    ]} == parse(ctx)
  end

  test "Foo.Bar.abc(%{a: a}) when is_integer(a) or is_binary(a) :: return(stack)", ctx do
    assert {Foo.Bar, :abc, [
      {[%{a: :"$1"}], [{:orelse, {:is_integer, :"$1"}, {:is_binary, :"$1"}}], [:return_stack]}
    ]} == parse(ctx)
  end

  test "Foo.Bar.abc(%{a: a}) when is_integer(a) or is_binary(a) :: return", ctx do
    assert {Foo.Bar, :abc, [
      {[%{a: :"$1"}], [{:orelse, {:is_integer, :"$1"}, {:is_binary, :"$1"}}], [:return_trace]}
    ]} == parse(ctx)
  end

  test "Foo.Bar.abc(%{a: a}) when is_integer(a) or is_binary(a)", ctx do
    assert {Foo.Bar, :abc, [
      {[%{a: :"$1"}], [{:orelse, {:is_integer, :"$1"}, {:is_binary, :"$1"}}], [:ok]}
    ]} == parse(ctx)
  end

  test "{Foo.Bar, :_, :_}", ctx do
    assert {Foo.Bar, :_, :_} == parse(ctx)
  end

  test "{:foo, :_, :_}", ctx do
    assert {:foo, :_, :_} == parse(ctx)
  end

  test "{Foo.Bar, :abc, :_}", ctx do
    assert {Foo.Bar, :abc, :_} == parse(ctx)
  end

  test "{:foo, :bar, :_}", ctx do
    assert {:foo, :bar, :_} == parse(ctx)
  end

  test "{Foo.Bar, :abc, fn(_) -> :return end}", ctx do
    assert {Foo.Bar, :abc, [
      {:_, [], [:return_trace]}
    ]} == parse(ctx)
  end

  test "{:foo, :bar, fn(_) -> :return end}", ctx do
    assert {:foo, :bar, [
      {:_, [], [:return_trace]}
    ]} == parse(ctx)
  end

  test "{Foo.Bar, :abc, fn(_) -> :return_trace end}", ctx do
    assert {Foo.Bar, :abc, [
      {:_, [], [:return_trace]}
    ]} == parse(ctx)
  end

  test "{:foo, :bar, fn(_) -> :return_trace end}", ctx do
    assert {:foo, :bar, [
      {:_, [], [:return_trace]}
    ]} == parse(ctx)
  end

  test "{Foo.Bar, :abc, fn([a, _]) when a == 1 -> :return end}", ctx do
    assert {Foo.Bar, :abc, [
      {[:"$1", :_], [{:==, :"$1", 1}], [:return_trace]}
    ]} == parse(ctx)
  end

  test "{:foo, :bar, fn([a, _]) when a == 1 -> :return end}", ctx do
    assert {:foo, :bar, [
      {[:"$1", :_], [{:==, :"$1", 1}], [:return_trace]}
    ]} == parse(ctx)
  end

  test "{[:foo, :bar], :_, :_}", ctx do
    assert {:error, reason} = parse(ctx)
    assert "invalid spec: {[:foo, :bar], :_, :_}" == reason
  end

  test "{:foo, [:bar, :abc], :_}", ctx do
    assert {:error, reason} = parse(ctx)
    assert "invalid spec: {:foo, [:bar, :abc], :_}" == reason
  end

  test "{:foo, :bar, :abc}", ctx do
    assert {:error, reason} = parse(ctx)
    assert "invalid arguments: :abc" == reason
  end

  test "{:foo, :bar, fn -> :ok end}", ctx do
    capture_io(fn ->
      assert {:error, reason} = parse(ctx)
      assert "fun2ms error: fn -> :ok end" == reason
    end)
  end

  test "{:foo, :bar, fn _, _ -> :ok end}", ctx do
    capture_io(fn ->
      assert {:error, reason} = parse(ctx)
      assert "fun2ms error: fn _, _ -> :ok end" == reason
    end)
  end

  test "{:foo, :bar, \"binary\"}", ctx do
    assert {:error, reason} = parse(ctx)
    assert "invalid arguments: \"binary\"" == reason
  end

  test "{:foo}", ctx do
    assert {:error, reason} = parse(ctx)
    assert "invalid spec: {:foo}" == reason
  end

  test "{:foo, :bar}", ctx do
    assert {:error, reason} = parse(ctx)
    assert "invalid spec: {:foo, :bar}" == reason
  end

  test "Foo.Bar.abc/any", ctx do
    assert {:error, reason} = parse(ctx)
    assert "invalid arguments: any" == reason
  end

  test "Foo.Bar.abc(a) when ::", ctx do
    assert {:error, reason} = parse(ctx)
    assert {[line: 1, column: 21], "syntax error before: ", "'::'"} == reason
  end

  test "Foo.Bar.abc(a)(b)", ctx do
    assert {:error, reason} = parse(ctx)
    assert "invalid spec: Foo.Bar.abc(a)(b)" == reason
  end

  test ":: return", ctx do
    assert {:error, reason} = parse(ctx)
    assert {[line: 1, column: 1], "syntax error before: ", "'::'"} == reason
  end

  test "any", ctx do
    assert {:error, reason} = parse(ctx)
    assert "invalid spec: any" == reason
  end

  test "[]", ctx do
    assert [] = parse(ctx)
  end

  defp parse(%{test: test}) do
    parse(String.replace_prefix(to_string(test), "test ", ""))
  end

  defp parse(term) do
    case Spec.parse_string(term) do
      {:ok, spec} -> spec
      {:error, r} -> {:error, r}
    end
  end
end
