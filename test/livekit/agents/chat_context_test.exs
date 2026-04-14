defmodule Livekit.Agents.ChatContextTest do
  use ExUnit.Case, async: true

  alias Livekit.Agents.ChatContext
  alias Livekit.Agents.ChatContext.{ChatMessage, FunctionCall, FunctionCallOutput}

  # CHAT-01: ChatMessage struct
  describe "ChatMessage struct" do
    test "new_message/2 returns a ChatMessage with expected fields" do
      msg = ChatContext.new_message(:user, ["Hello"])
      assert %ChatMessage{} = msg
      assert msg.role == :user
      assert msg.content == ["Hello"]
      assert msg.interrupted == false
      assert is_binary(msg.id)
      assert byte_size(msg.id) > 0
      assert %DateTime{} = msg.created_at
    end

    test "new_message/2 supports all valid roles" do
      for role <- [:system, :user, :assistant, :tool] do
        msg = ChatContext.new_message(role, ["text"])
        assert msg.role == role
      end
    end

    test "new_message/2 rejects invalid roles" do
      assert_raise FunctionClauseError, fn ->
        ChatContext.new_message(:invalid, ["text"])
      end
    end

    test "new_message/2 generates unique ids" do
      msg1 = ChatContext.new_message(:user, ["a"])
      msg2 = ChatContext.new_message(:user, ["b"])
      assert msg1.id != msg2.id
    end
  end

  # CHAT-02: FunctionCall struct
  describe "FunctionCall struct" do
    test "new_function_call/3 returns a FunctionCall with expected fields" do
      fc = ChatContext.new_function_call("cid-1", "get_weather", ~s({"city":"London"}))
      assert %FunctionCall{} = fc
      assert fc.call_id == "cid-1"
      assert fc.name == "get_weather"
      assert fc.arguments == ~s({"city":"London"})
      assert is_binary(fc.id)
      assert %DateTime{} = fc.created_at
    end

    test "new_function_call/3 generates unique ids" do
      fc1 = ChatContext.new_function_call("cid-1", "fn", "{}")
      fc2 = ChatContext.new_function_call("cid-2", "fn", "{}")
      assert fc1.id != fc2.id
    end
  end

  # CHAT-03: FunctionCallOutput struct
  describe "FunctionCallOutput struct" do
    test "new_function_call_output/4 returns a FunctionCallOutput with expected fields" do
      fco = ChatContext.new_function_call_output("cid-1", "get_weather", "Rainy, 15C")
      assert %FunctionCallOutput{} = fco
      assert fco.call_id == "cid-1"
      assert fco.name == "get_weather"
      assert fco.output == "Rainy, 15C"
      assert fco.is_error == false
      assert is_binary(fco.id)
      assert %DateTime{} = fco.created_at
    end

    test "new_function_call_output/4 sets is_error when true" do
      fco = ChatContext.new_function_call_output("cid-1", "fn", "err msg", true)
      assert fco.is_error == true
    end

    test "new_function_call_output/4 defaults is_error to false" do
      fco = ChatContext.new_function_call_output("cid-1", "fn", "ok")
      assert fco.is_error == false
    end
  end

  # CHAT-06: Multi-modal content
  describe "multi-modal content (CHAT-06)" do
    test "ChatMessage content accepts list of plain strings" do
      msg = ChatContext.new_message(:user, ["Hello there"])
      assert msg.content == ["Hello there"]
    end

    test "ChatMessage content accepts list of maps (structured data)" do
      content = [%{"type" => "image_url", "url" => "https://example.com/img.jpg"}]
      msg = ChatContext.new_message(:user, content)
      assert msg.content == content
    end

    test "ChatMessage content accepts mixed strings and maps" do
      content = ["Describe this:", %{"type" => "image_url", "url" => "https://example.com/a.jpg"}]
      msg = ChatContext.new_message(:user, content)
      assert msg.content == content
    end

    test "ChatMessage content accepts empty list" do
      msg = ChatContext.new_message(:assistant, [])
      assert msg.content == []
    end
  end

  # CHAT-04: ChatContext.new/0
  describe "ChatContext.new/0" do
    test "creates an empty context" do
      ctx = ChatContext.new()
      assert %ChatContext{} = ctx
      assert ctx.items == []
    end
  end

  # CHAT-04: ChatContext.add/2
  describe "ChatContext.add/2" do
    test "appends a ChatMessage" do
      ctx = ChatContext.new()
      msg = ChatContext.new_message(:user, ["hi"])
      ctx = ChatContext.add(ctx, msg)
      assert length(ctx.items) == 1
      assert hd(ctx.items) == msg
    end

    test "appends items in insertion order (oldest-first)" do
      msg1 = ChatContext.new_message(:user, ["first"])
      msg2 = ChatContext.new_message(:assistant, ["second"])
      ctx = ChatContext.new() |> ChatContext.add(msg1) |> ChatContext.add(msg2)
      assert ctx.items == [msg1, msg2]
    end

    test "appends FunctionCall and FunctionCallOutput items" do
      fc = ChatContext.new_function_call("cid", "fn", "{}")
      fco = ChatContext.new_function_call_output("cid", "fn", "result")
      ctx = ChatContext.new() |> ChatContext.add(fc) |> ChatContext.add(fco)
      assert length(ctx.items) == 2
    end
  end

  # CHAT-04: ChatContext.messages/1
  describe "ChatContext.messages/1" do
    test "returns only ChatMessage items" do
      msg = ChatContext.new_message(:user, ["hi"])
      fc = ChatContext.new_function_call("cid", "fn", "{}")
      fco = ChatContext.new_function_call_output("cid", "fn", "result")

      ctx =
        ChatContext.new() |> ChatContext.add(msg) |> ChatContext.add(fc) |> ChatContext.add(fco)

      assert ChatContext.messages(ctx) == [msg]
    end

    test "returns empty list when no ChatMessages" do
      fc = ChatContext.new_function_call("cid", "fn", "{}")
      ctx = ChatContext.new() |> ChatContext.add(fc)
      assert ChatContext.messages(ctx) == []
    end
  end

  # CHAT-04, CHAT-05: ChatContext.truncate/2
  describe "ChatContext.truncate/2 (CHAT-04, CHAT-05)" do
    test "keeps all items when under limit" do
      msgs = for i <- 1..3, do: ChatContext.new_message(:user, ["msg #{i}"])
      ctx = Enum.reduce(msgs, ChatContext.new(), &ChatContext.add(&2, &1))
      truncated = ChatContext.truncate(ctx, 10)
      assert length(truncated.items) == 3
    end

    test "drops oldest items when over limit" do
      msgs = for i <- 1..5, do: ChatContext.new_message(:user, ["msg #{i}"])
      ctx = Enum.reduce(msgs, ChatContext.new(), &ChatContext.add(&2, &1))
      truncated = ChatContext.truncate(ctx, 3)
      assert length(truncated.items) == 3
      # Should keep the last 3
      assert Enum.map(truncated.items, & &1.content) == [["msg 3"], ["msg 4"], ["msg 5"]]
    end

    test "preserves leading system message even when truncating (CHAT-05)" do
      sys = ChatContext.new_message(:system, ["You are helpful."])
      user_msgs = for i <- 1..5, do: ChatContext.new_message(:user, ["msg #{i}"])

      ctx =
        Enum.reduce(user_msgs, ChatContext.add(ChatContext.new(), sys), &ChatContext.add(&2, &1))

      truncated = ChatContext.truncate(ctx, 2)
      assert hd(truncated.items) == sys
      # 1 system + 2 non-system = 3 total
      assert length(truncated.items) == 3
    end

    test "preserves multiple leading system messages" do
      sys1 = ChatContext.new_message(:system, ["Instruction 1."])
      sys2 = ChatContext.new_message(:system, ["Instruction 2."])
      user_msgs = for i <- 1..4, do: ChatContext.new_message(:user, ["msg #{i}"])

      ctx =
        [sys1, sys2 | user_msgs]
        |> Enum.reduce(ChatContext.new(), &ChatContext.add(&2, &1))

      truncated = ChatContext.truncate(ctx, 2)
      [first, second | _] = truncated.items
      assert first == sys1
      assert second == sys2
      assert length(truncated.items) == 4
    end

    test "drops orphaned FunctionCallOutput at truncation boundary" do
      fc = ChatContext.new_function_call("cid-1", "fn", "{}")
      fco = ChatContext.new_function_call_output("cid-1", "fn", "result")
      user = ChatContext.new_message(:user, ["hello"])
      # items: [fc, fco, user] — truncate to 2 keeps [fco, user]
      # but fco is orphaned (fc was dropped), so it should be dropped too
      ctx =
        ChatContext.new() |> ChatContext.add(fc) |> ChatContext.add(fco) |> ChatContext.add(user)

      truncated = ChatContext.truncate(ctx, 2)
      # fco is orphaned at the boundary; only user should remain (plus no system msgs)
      refute Enum.any?(truncated.items, &match?(%FunctionCallOutput{}, &1))
      assert Enum.any?(truncated.items, &match?(%ChatMessage{role: :user}, &1))
    end

    test "does NOT drop FunctionCallOutput when its FunctionCall is present" do
      fc = ChatContext.new_function_call("cid-1", "fn", "{}")
      fco = ChatContext.new_function_call_output("cid-1", "fn", "result")
      ctx = ChatContext.new() |> ChatContext.add(fc) |> ChatContext.add(fco)
      truncated = ChatContext.truncate(ctx, 10)
      assert length(truncated.items) == 2
    end

    test "truncate/2 rejects non-positive max_items" do
      ctx = ChatContext.new()
      assert_raise FunctionClauseError, fn -> ChatContext.truncate(ctx, 0) end
      assert_raise FunctionClauseError, fn -> ChatContext.truncate(ctx, -1) end
    end
  end

  # CHAT-04: ChatContext.copy/1
  describe "ChatContext.copy/1" do
    test "returns a new struct with the same items" do
      msg = ChatContext.new_message(:user, ["hi"])
      ctx = ChatContext.add(ChatContext.new(), msg)
      copy = ChatContext.copy(ctx)
      assert copy.items == ctx.items
      assert copy == ctx
    end

    test "copy returns an empty context for empty input" do
      ctx = ChatContext.new()
      copy = ChatContext.copy(ctx)
      assert copy.items == []
    end
  end

  # CHAT-04: ChatContext.merge/2
  describe "ChatContext.merge/2" do
    test "adds non-duplicate items from other context" do
      msg1 = ChatContext.new_message(:user, ["first"])
      msg2 = ChatContext.new_message(:assistant, ["second"])
      ctx1 = ChatContext.add(ChatContext.new(), msg1)
      ctx2 = ChatContext.add(ChatContext.new(), msg2)
      merged = ChatContext.merge(ctx1, ctx2)
      assert length(merged.items) == 2
    end

    test "deduplicates items with the same id" do
      msg = ChatContext.new_message(:user, ["hi"])
      ctx1 = ChatContext.add(ChatContext.new(), msg)
      ctx2 = ChatContext.add(ChatContext.new(), msg)
      merged = ChatContext.merge(ctx1, ctx2)
      assert length(merged.items) == 1
    end

    test "sorts merged items by created_at ascending" do
      t1 = ~U[2026-01-01 10:00:00Z]
      t2 = ~U[2026-01-01 10:00:01Z]
      t3 = ~U[2026-01-01 10:00:02Z]

      msg1 = %ChatMessage{
        id: "a",
        role: :user,
        content: ["first"],
        interrupted: false,
        created_at: t1
      }

      msg3 = %ChatMessage{
        id: "c",
        role: :user,
        content: ["third"],
        interrupted: false,
        created_at: t3
      }

      msg2 = %ChatMessage{
        id: "b",
        role: :assistant,
        content: ["second"],
        interrupted: false,
        created_at: t2
      }

      ctx1 = ChatContext.add(ChatContext.new(), msg1) |> ChatContext.add(msg3)
      ctx2 = ChatContext.add(ChatContext.new(), msg2)
      merged = ChatContext.merge(ctx1, ctx2)
      assert length(merged.items) == 3
      assert Enum.map(merged.items, & &1.id) == ["a", "b", "c"]
    end

    test "merging two empty contexts yields empty context" do
      merged = ChatContext.merge(ChatContext.new(), ChatContext.new())
      assert merged.items == []
    end
  end

  # Jason encoding tests
  describe "Jason encoding" do
    test "ChatMessage encodes to JSON without error" do
      msg = ChatContext.new_message(:user, ["Hello"])
      json = Jason.encode!(msg)
      assert is_binary(json)
      decoded = Jason.decode!(json)
      assert decoded["role"] == "user"
      assert decoded["content"] == ["Hello"]
      assert decoded["interrupted"] == false
      assert is_binary(decoded["id"])
      assert is_binary(decoded["created_at"])
      # created_at should be ISO 8601
      assert String.contains?(decoded["created_at"], "T")
    end

    test "ChatMessage with map content encodes correctly" do
      content = ["Describe:", %{"type" => "image_url", "url" => "https://example.com/a.jpg"}]
      msg = ChatContext.new_message(:user, content)
      json = Jason.encode!(msg)
      decoded = Jason.decode!(json)
      assert length(decoded["content"]) == 2
      assert is_map(List.last(decoded["content"]))
    end

    test "FunctionCall encodes to JSON without error" do
      fc = ChatContext.new_function_call("cid-1", "get_weather", ~s({"city":"London"}))
      json = Jason.encode!(fc)
      decoded = Jason.decode!(json)
      assert decoded["call_id"] == "cid-1"
      assert decoded["name"] == "get_weather"
      assert decoded["arguments"] == ~s({"city":"London"})
      assert is_binary(decoded["created_at"])
    end

    test "FunctionCallOutput encodes to JSON without error" do
      fco = ChatContext.new_function_call_output("cid-1", "get_weather", "Rainy", true)
      json = Jason.encode!(fco)
      decoded = Jason.decode!(json)
      assert decoded["call_id"] == "cid-1"
      assert decoded["output"] == "Rainy"
      assert decoded["is_error"] == true
      assert is_binary(decoded["created_at"])
    end

    test "FunctionCallOutput with default is_error encodes is_error as false" do
      fco = ChatContext.new_function_call_output("cid-2", "fn", "ok")
      decoded = Jason.decode!(Jason.encode!(fco))
      assert decoded["is_error"] == false
    end

    test "all four roles encode as their string equivalent" do
      for {role, expected} <- [
            system: "system",
            user: "user",
            assistant: "assistant",
            tool: "tool"
          ] do
        msg = ChatContext.new_message(role, [])
        decoded = Jason.decode!(Jason.encode!(msg))

        assert decoded["role"] == expected,
               "Expected role #{inspect(expected)} but got #{inspect(decoded["role"])}"
      end
    end
  end
end
