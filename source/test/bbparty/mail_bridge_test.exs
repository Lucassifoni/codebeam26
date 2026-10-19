defmodule Bbparty.MailBridgeTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias Bbparty.MailBridge

  defp start_bridge(opts) do
    test = self()

    defaults = [
      name: nil,
      server: "imap.example.org",
      username: "demo@example.org",
      password: "secret",
      connect: fn client_opts ->
        send(test, {:connect, client_opts})
        {:ok, spawn_link(fn -> receive do: (:stop -> :ok) end)}
      end,
      publish: fn module_id, body -> send(test, {:frame, module_id, body}) end,
      resolve: fn
        :align_left -> [:on_screen_align_left, :button_6]
        :align_center -> [:button_5]
      end,
      retry_ms: 0,
      hold_ms: 0
    ]

    start_supervised!({MailBridge, Keyword.merge(defaults, opts)})
  end

  defp mail(pid, subject, from \\ "someone@example.org") do
    send(pid, {:email, :client, %{subject: subject, from: [{"Someone", from}]}})
  end

  describe "key_indices/1" do
    test "keeps module_2 keys only, in order, once each" do
      assert MailBridge.key_indices([:on_screen, :button_6, "button_5", :button_6, :key_3]) ==
               [6, 5]
    end
  end

  describe "a mail naming an action" do
    test "presses then releases the key carrying it" do
      mail(start_bridge([]), "Gauche")

      assert_receive {:frame, 0x02, <<0x82, 6, 1>>}
      assert_receive {:frame, 0x02, <<0x82, 6, 0>>}
    end

    test "resolves through the layout, not a table" do
      mail(start_bridge(resolve: fn _ -> [:button_3] end), "align_center")

      assert_receive {:frame, 0x02, <<0x82, 3, 1>>}
    end
  end

  describe "mail that presses nothing" do
    test "an unrecognised subject" do
      mail(start_bridge([]), "Bonjour")

      refute_receive {:frame, _, _}, 50
    end

    test "an action no module_2 key carries" do
      mail(start_bridge(resolve: fn _ -> [:on_screen_align_left] end), "gauche")

      refute_receive {:frame, _, _}, 50
    end

    test "a mail without a subject" do
      mail(start_bridge([]), nil)

      refute_receive {:frame, _, _}, 50
    end
  end

  describe "accepted?/2" do
    test "any sender when unrestricted" do
      assert MailBridge.accepted?(%{from: [{nil, "x@example.org"}]}, :any)
    end

    test "a listed From address, whatever its case" do
      allowed = ["lucas@example.org"]

      assert MailBridge.accepted?(%{from: [{"L", "Lucas@Example.org"}]}, allowed)
      assert MailBridge.accepted?(%{from: [{nil, "x@y.z"}, {nil, "lucas@example.org"}]}, allowed)
      refute MailBridge.accepted?(%{from: [{"L", "lucas@example.org.evil"}]}, allowed)
      refute MailBridge.accepted?(%{from: []}, allowed)
      refute MailBridge.accepted?(%{}, allowed)
    end
  end

  describe "with allowed senders" do
    test "a listed sender presses" do
      pid = start_bridge(allowed_senders: ["lucas@example.org"])
      mail(pid, "gauche", "lucas@example.org")

      assert_receive {:frame, 0x02, <<0x82, 6, 1>>}
    end

    test "anyone else is ignored" do
      pid = start_bridge(allowed_senders: ["lucas@example.org"])
      mail(pid, "gauche", "someone@example.org")

      refute_receive {:frame, _, _}, 50
    end
  end

  describe "the IMAP client" do
    defp connecting(test, outcome) do
      fn opts ->
        client = outcome.()
        send(test, {:connected, opts, client})
        client
      end
    end

    defp client, do: {:ok, spawn_link(fn -> receive do: (:stop -> :ok) end)}

    test "is started with the configured credentials" do
      start_bridge(connect: connecting(self(), &client/0))

      assert_receive {:connected, opts, _}
      assert opts[:server] == "imap.example.org"
      assert opts[:username] == "demo@example.org"
      assert opts[:password] == "secret"
    end

    test "is restarted after it exits, even normally" do
      start_bridge(connect: connecting(self(), &client/0))

      assert_receive {:connected, _, {:ok, first}}
      send(first, :stop)

      assert_receive {:connected, _, {:ok, second}}
      assert second != first
    end

    test "is retried when it cannot be started" do
      attempts = :counters.new(1, [])

      outcome = fn ->
        :counters.add(attempts, 1, 1)

        case :counters.get(attempts, 1) do
          1 -> {:error, :nxdomain}
          _ -> client()
        end
      end

      start_bridge(connect: connecting(self(), outcome))

      assert_receive {:connected, _, {:error, :nxdomain}}
      assert_receive {:connected, _, {:ok, _pid}}
    end
  end
end
