defmodule Bbparty.TagProgrammer.StateTest do
  use ExUnit.Case, async: true

  alias Bbparty.TagProgrammer.State

  defp verify_ok(state, text) do
    {state, []} = State.handle_event(state, {:tag_read, %{uid: <<1>>, sak: 0, text: text}})
    State.handle_event(state, {:write_result, %{ok: true, uid: <<1>>}})
  end

  test "new/1 builds pending items in order" do
    state = State.new(["a", "b", "c"])
    assert length(state.items) == 3
    assert Enum.map(state.items, & &1.text) == ["a", "b", "c"]
    assert Enum.all?(state.items, &(&1.status == :pending))
    assert state.phase == :idle
  end

  test "start on an empty list completes immediately" do
    assert {%State{phase: :complete}, []} = State.start(State.new([]))
  end

  test "start emits a write for the first line and awaits the tag" do
    {state, effects} = State.start(State.new(["HELLO"]))
    assert effects == [{:write_tag, "HELLO"}]
    assert state.phase == :awaiting_tag
    assert State.current(state).status == :writing
  end

  test "happy path programs every line, one per removal" do
    {state, [{:write_tag, "one"}]} = State.start(State.new(["one", "two"]))

    {state, []} = verify_ok(state, "one")
    assert state.phase == :awaiting_removal
    assert Enum.at(state.items, 0).status == :done
    assert Enum.at(state.items, 0).read == "one"

    {state, [{:write_tag, "two"}]} = State.handle_event(state, {:tag_gone})
    assert state.phase == :awaiting_tag

    {state, []} = verify_ok(state, "two")
    {state, []} = State.handle_event(state, {:tag_gone})
    assert state.phase == :complete
    assert State.summary(state) == %{total: 2, done: 2, failed: 0}
  end

  test "read-back mismatch fails the line and retry re-writes it" do
    {state, _} = State.start(State.new(["good"]))

    {state, []} = State.handle_event(state, {:tag_read, %{uid: <<1>>, sak: 0, text: "bad"}})
    {state, []} = State.handle_event(state, {:write_result, %{ok: true, uid: <<1>>}})
    assert state.phase == :failed
    assert Enum.at(state.items, 0).status == :failed
    assert state.error =~ "mismatch"

    {state, [{:write_tag, "good"}]} = State.retry(state)
    assert state.phase == :awaiting_tag

    {state, []} = verify_ok(state, "good")
    assert state.phase == :awaiting_removal
    assert Enum.at(state.items, 0).status == :done
  end

  test "a device-reported write failure fails the line" do
    {state, _} = State.start(State.new(["x"]))
    {state, []} = State.handle_event(state, {:tag_read, %{uid: <<1>>, sak: 0, text: "x"}})
    {state, []} = State.handle_event(state, {:write_result, %{ok: false, uid: <<1>>}})
    assert state.phase == :failed
    assert state.error =~ "failed"
  end

  test "skip marks the line skipped and advances" do
    {state, _} = State.start(State.new(["a", "b"]))
    {state, [{:write_tag, "b"}]} = State.skip(state)
    assert Enum.at(state.items, 0).status == :skipped
    assert state.phase == :awaiting_tag

    {state, []} = verify_ok(state, "b")
    {state, []} = State.handle_event(state, {:tag_gone})
    assert state.phase == :complete
    assert State.summary(state) == %{total: 2, done: 1, failed: 0}
  end

  test "events are ignored while idle or complete" do
    idle = State.new(["a"])
    assert {^idle, []} = State.handle_event(idle, {:tag_gone})

    {complete, []} = State.start(State.new([]))
    assert {^complete, []} = State.handle_event(complete, {:write_result, %{ok: true, uid: <<>>}})
  end
end
