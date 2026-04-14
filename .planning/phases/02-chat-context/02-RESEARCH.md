# Phase 2: Chat Context - Research

**Researched:** 2026-04-14
**Domain:** Elixir typed structs, Jason encoding, conversation context management
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
None locked by user — all implementation choices are at Claude's discretion.

### Claude's Discretion
All implementation choices are at Claude's discretion. Key constraints from prior phases and project context:
- Follow existing codebase conventions (nested Config structs, {:ok, result} / {:error, reason} tuples)
- ChatMessage roles: system, user, assistant, tool (matching Python agents ChatMessage.role)
- ChatContext should be a struct with an ordered list of ChatItem entries
- FunctionCall needs: call_id, name, arguments fields
- FunctionCallOutput needs: call_id, result, error flag
- Truncation must preserve system messages regardless of token budget
- Support multi-modal content (plain text strings and structured maps)
- Implement Jason.Encoder for all structs to ensure round-trip encoding

### Deferred Ideas (OUT OF SCOPE)
None.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CHAT-01 | Define `ChatMessage` struct with id, role (system/user/assistant/tool), content, timestamp | Struct design documented in Architecture Patterns |
| CHAT-02 | Define `FunctionCall` struct with call_id, name, arguments | Struct design and field rationale documented |
| CHAT-03 | Define `FunctionCallOutput` struct with call_id, result, error flag | Struct design and Jason encoding path documented |
| CHAT-04 | Define `ChatContext` module with add, truncate, merge, copy operations | Operation semantics documented with exact Python reference parity |
| CHAT-05 | ChatContext preserves system messages during truncation | Truncation algorithm documented; must reinsert system messages if removed |
| CHAT-06 | ChatContext supports multi-modal content types (text, structured) | Content tagged union via `{:text, binary()}` and `{:data, map()}` documented |
| TEST-02 | 100% test coverage for ChatContext and tool system | ExUnit + ExCoveralls, no new deps needed; Wave 0 test files listed |
</phase_requirements>

---

## Summary

Phase 2 delivers pure Elixir data structures — no GenServers, no HTTP, no external services. The work is entirely in `lib/livekit/agents/chat_context.ex` (or possibly split across a few modules) and a corresponding test file. This is the foundational data layer that every downstream phase (tool system, OpenAI provider, voice pipeline) depends on.

The Python livekit-agents framework provides a clear reference for API design. Its `ChatContext` is an ordered collection of typed items (ChatMessage, FunctionCall, FunctionCallOutput), each carrying a timestamp for sort-stable ordering. Truncation works by slicing from the tail of non-system messages, then reinserting any system message that was removed. The Elixir implementation should mirror this semantics while using idiomatic Elixir patterns (structs, tagged tuples, `@derive [Jason.Encoder]` or `defimpl Jason.Encoder`).

Jason ~> 1.4 is already in `mix.exs`. ExCoveralls is already configured. No new dependencies are required for this phase.

**Primary recommendation:** Implement ChatMessage, FunctionCall, FunctionCallOutput, and ChatContext as nested structs inside `Livekit.Agents.ChatContext` module. Use `@derive [Jason.Encoder]` for automatic encoding. Use message-count-based truncation (not token counting — defer token counting to the OpenAI provider in Phase 5).

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Jason | ~> 1.4 (locked 1.4.4) | JSON encode/decode for round-trip | Already in mix.exs; project uses it for Tesla middleware |
| ExUnit | bundled | Test framework | Standard Elixir test framework |
| ExCoveralls | ~> 0.18 | Coverage measurement | Already configured with `test_coverage: [tool: ExCoveralls]` |

[VERIFIED: mix.exs and mix.lock in codebase]

### No New Dependencies Required

All libraries needed for this phase are already present. [VERIFIED: codebase]

**Installation:** None required — all deps already in `mix.exs`.

---

## Architecture Patterns

### Recommended Module Layout

All types live in a single file to keep them co-located and avoid circular deps with future tool system modules:

```
lib/livekit/agents/
└── chat_context.ex   # ChatContext + nested ChatMessage, FunctionCall, FunctionCallOutput
```

Alternatively, separate files work if modules get large:
```
lib/livekit/agents/
├── chat_context.ex          # ChatContext struct + operations
└── chat_context/
    ├── chat_message.ex      # ChatMessage struct
    ├── function_call.ex     # FunctionCall struct
    └── function_call_output.ex  # FunctionCallOutput struct
```

Single-file is preferred for phase 2 (simpler, fewer compile units, easier to refactor in Phase 3 if needed).

### Pattern 1: ChatMessage Struct

```elixir
# Source: codebase conventions (CONVENTIONS.md) + Python agents reference
defmodule Livekit.Agents.ChatContext do
  @moduledoc """
  Typed conversation context for LLM providers.
  ...
  """

  defmodule ChatMessage do
    @moduledoc """
    A single conversation message.
    """

    @type role :: :system | :user | :assistant | :tool

    # Content is a list to support multi-modal: strings and structured maps.
    # Text-only messages: ["Hello there"]
    # Multi-modal messages: ["Describe this:", %{type: "image_url", url: "..."}]
    @type content_item :: String.t() | map()

    @type t :: %__MODULE__{
      id: String.t(),
      role: role(),
      content: [content_item()],
      interrupted: boolean(),
      created_at: DateTime.t()
    }

    @derive {Jason.Encoder, only: [:id, :role, :content, :interrupted, :created_at]}
    defstruct [:id, :role, :content, :interrupted, :created_at]
  end
end
```

**Why a list for content:** The Python reference uses a list of mixed strings and structured objects (ImageContent, AudioContent). An Elixir list of `String.t() | map()` provides the same flexibility without pulling in Pydantic-style unions. Pattern matching on list items works cleanly. [CITED: docs.livekit.io/python/livekit/agents/llm/index.html]

**Why not tagged tuples for content items:** `{:text, "hello"}` vs `map()` — keeping it compatible with direct JSON round-trip is simpler. Plain strings encode as JSON strings; maps encode as JSON objects. Tagged tuples would require a custom Jason encoder. The `String.t() | map()` union encodes naturally with `@derive Jason.Encoder`.

### Pattern 2: FunctionCall Struct

```elixir
defmodule FunctionCall do
  @moduledoc """
  A tool/function call request from the LLM.
  """

  @type t :: %__MODULE__{
    id: String.t(),
    call_id: String.t(),
    name: String.t(),
    arguments: String.t(),   # JSON-encoded argument string (matches OpenAI API format)
    created_at: DateTime.t()
  }

  @derive [Jason.Encoder]
  defstruct [:id, :call_id, :name, :arguments, :created_at]
end
```

**Why `arguments` as `String.t()`:** OpenAI tool calling returns arguments as a JSON string, not a parsed map. Storing as a string preserves fidelity and avoids double-encoding. Callers decode with `Jason.decode!/1` when executing. [CITED: docs.livekit.io/python/livekit/agents/llm/index.html]

### Pattern 3: FunctionCallOutput Struct

```elixir
defmodule FunctionCallOutput do
  @moduledoc """
  Result of executing a tool call, to be fed back to the LLM.
  """

  @type t :: %__MODULE__{
    id: String.t(),
    call_id: String.t(),
    name: String.t(),
    output: String.t(),   # Result as string
    is_error: boolean(),
    created_at: DateTime.t()
  }

  @derive [Jason.Encoder]
  defstruct [:id, :call_id, :name, :output, is_error: false, :created_at]
end
```

### Pattern 4: ChatContext Struct and Operations

```elixir
@type chat_item :: ChatMessage.t() | FunctionCall.t() | FunctionCallOutput.t()

@type t :: %__MODULE__{
  items: [chat_item()]    # Ordered oldest-first
}

defstruct items: []
```

**Operations:**

```elixir
# add/2 — append to end (chronological)
@spec add(t(), chat_item()) :: t()
def add(%__MODULE__{} = ctx, item) do
  %{ctx | items: ctx.items ++ [item]}
end

# messages/1 — filter to ChatMessage items only
@spec messages(t()) :: [ChatMessage.t()]
def messages(%__MODULE__{} = ctx) do
  Enum.filter(ctx.items, &match?(%ChatMessage{}, &1))
end

# truncate/2 — keep last N items, never drop system messages
@spec truncate(t(), pos_integer()) :: t()
def truncate(%__MODULE__{} = ctx, max_items) do
  # 1. Extract system messages from the front
  {system_items, rest} = Enum.split_while(ctx.items, fn
    %ChatMessage{role: :system} -> true
    _ -> false
  end)
  # 2. Take last max_items from the rest
  truncated_rest = Enum.take(rest, -max_items)
  # 3. Reinsert system messages at the front
  %{ctx | items: system_items ++ truncated_rest}
end

# copy/1 — shallow struct copy
@spec copy(t()) :: t()
def copy(%__MODULE__{} = ctx), do: %{ctx | items: ctx.items}

# merge/2 — add items from other context, deduplicating by id
@spec merge(t(), t()) :: t()
def merge(%__MODULE__{} = ctx, %__MODULE__{} = other) do
  existing_ids = MapSet.new(ctx.items, & &1.id)
  new_items = Enum.reject(other.items, &MapSet.member?(existing_ids, &1.id))
  all_items = ctx.items ++ new_items
  sorted = Enum.sort_by(all_items, & &1.created_at, DateTime)
  %{ctx | items: sorted}
end
```

### Pattern 5: ID Generation

Use `System.unique_integer([:positive, :monotonic])` converted to a binary string, or use `:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)`. The latter is safer for distributed use. [ASSUMED — both are idiomatic; random bytes is more collision-resistant]

### Pattern 6: Jason.Encoder for DateTime

`DateTime.t()` does NOT have a built-in Jason encoder — it must be handled. Two options:

**Option A:** `@derive {Jason.Encoder, only: [...fields...]}` and convert `created_at` to ISO 8601 string before encoding. This requires a custom `defimpl Jason.Encoder` or pre-serialization step.

**Option B:** Store `created_at` as an ISO 8601 string internally (simpler for encoding, but loses DateTime semantics for sorting).

**Recommended:** Store as `DateTime.t()` for sort operations; implement `defimpl Jason.Encoder, for: Livekit.Agents.ChatContext.ChatMessage` (and siblings) that renders `created_at` via `DateTime.to_iso8601/1`. This gives full control. [VERIFIED: Jason 1.4 docs — structs need either `@derive [Jason.Encoder]` for simple field pass-through or `defimpl Jason.Encoder` for custom rendering]

Note: `@derive [Jason.Encoder]` on a struct that contains a `DateTime` will fail at encode time because Jason has no built-in DateTime encoder. Use `defimpl Jason.Encoder` with explicit field rendering, or derive with only non-DateTime fields and use a pre-serialization function.

### Anti-Patterns to Avoid

- **Storing items newest-first (prepend):** The existing `VoiceAgent` uses `[new | existing]` (newest-first list). ChatContext items must be stored oldest-first to match Python reference and make `Enum.take(rest, -N)` work correctly for truncation. [ASSUMED based on Python reference semantics]
- **Atom roles in JSON output:** OpenAI API expects string roles ("system", "user"). The `to_openai_messages/1` helper (or the OpenAI provider in Phase 5) handles the `Atom.to_string/1` conversion. ChatContext stores roles as atoms internally — do not auto-serialize atoms to strings in Jason.Encoder unless that's the intended format.
- **Token counting in this phase:** Truncation by token count requires a tokenizer. Use message-count truncation (max_items integer) in Phase 2. The OpenAI provider (Phase 5) will handle token-aware truncation using the `max_context_tokens` from `capabilities/0`.
- **Using `|>` on structs with `++`:** `items ++ [new_item]` on each `add/2` is O(n). For high-frequency add, use a reversed list internally and reverse only on `messages/1`. However, for voice agent workloads (dozens to hundreds of messages), O(n) append is acceptable. Document the tradeoff.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON encoding | Custom binary serializer | `@derive [Jason.Encoder]` or `defimpl Jason.Encoder` | Jason handles escaping, Unicode, nested structures |
| Unique IDs | Custom counter | `:crypto.strong_rand_bytes(16) \|> Base.encode16()` | Collision-resistant, no coordination required |
| Sort stability | Custom sort | `Enum.sort_by(items, & &1.created_at, DateTime)` | DateTime comparison is built-in via `Calendar.datetime/0` |

**Key insight:** This phase is pure data modeling. The only complexity is the truncation invariant (system message preservation) and the Jason encoding of DateTime. Both have idiomatic Elixir solutions.

---

## Common Pitfalls

### Pitfall 1: Jason Cannot Encode DateTime Out of the Box

**What goes wrong:** `Jason.encode!(%ChatMessage{created_at: DateTime.utc_now()})` raises `Protocol.UndefinedError` for `Jason.Encoder` with `DateTime`.
**Why it happens:** Jason has no built-in encoder for `DateTime`. Only basic types (binary, atom, integer, float, list, map) are natively supported.
**How to avoid:** Implement `defimpl Jason.Encoder` for each struct and use `DateTime.to_iso8601(struct.created_at)` in the implementation.
**Warning signs:** Tests that call `Jason.encode!` on structs will crash at runtime if DateTime is not handled.

### Pitfall 2: `@derive [Jason.Encoder]` Encodes Atom Fields as Strings

**What goes wrong:** `role: :assistant` becomes `"role": "assistant"` in JSON output (fine), but `Jason.decode!` produces `"role" => "assistant"` (string key, string value) not `"role" => :assistant`. Round-trip through Jason does NOT produce the original struct.
**Why it happens:** JSON has no atom type. Jason decodes to string keys and string values.
**How to avoid:** Define a `from_json/1` or `new/1` constructor that converts string keys/values back to atoms using `String.to_existing_atom/1`. Document that decode requires a constructor, not bare `Jason.decode!`.
**Warning signs:** Tests like `assert Jason.decode!(Jason.encode!(msg)) == msg` will fail.

### Pitfall 3: Truncation Drops Leading FunctionCall/FunctionCallOutput Pairs

**What goes wrong:** Truncating mid-function-call-cycle leaves an orphaned FunctionCall without its FunctionCallOutput (or vice versa). Some LLMs reject contexts with unpaired tool calls.
**Why it happens:** Simple `Enum.take(items, -N)` can slice in the middle of a call/output pair.
**How to avoid:** After taking the last N items, scan the front of the truncated list and drop any leading FunctionCallOutput entries whose call_id has no corresponding FunctionCall in the remaining items. This is what the Python reference does. [CITED: docs.livekit.io/python/livekit/agents/llm/index.html]
**Warning signs:** Tool-calling tests will reveal this if they test truncation across a function call boundary.

### Pitfall 4: Incorrect Module Placement for Jason.Encoder impl

**What goes wrong:** `defimpl Jason.Encoder, for: ChatMessage` placed outside the parent module context causes compile-time alias resolution failures.
**Why it happens:** Nested module names must be fully qualified in `defimpl`.
**How to avoid:** Use the full module name: `defimpl Jason.Encoder, for: Livekit.Agents.ChatContext.ChatMessage`.

---

## Code Examples

### Implementing Jason.Encoder for a struct with DateTime

```elixir
# Source: Jason 1.4 docs — defimpl pattern for custom encoding
defimpl Jason.Encoder, for: Livekit.Agents.ChatContext.ChatMessage do
  def encode(msg, opts) do
    Jason.Encode.map(
      %{
        "id" => msg.id,
        "role" => Atom.to_string(msg.role),
        "content" => msg.content,
        "interrupted" => msg.interrupted,
        "created_at" => DateTime.to_iso8601(msg.created_at)
      },
      opts
    )
  end
end
```

### Deriving Jason.Encoder (works only when all fields are JSON-native)

```elixir
# Works only if there are NO DateTime or atom fields that need custom rendering
@derive {Jason.Encoder, only: [:id, :call_id, :name, :arguments]}
defstruct [:id, :call_id, :name, :arguments, :created_at]
# Note: created_at excluded from derive, handle separately if needed
```

### Truncation preserving system messages

```elixir
# Source: based on Python livekit-agents truncate() semantics
def truncate(%__MODULE__{} = ctx, max_items) when is_integer(max_items) and max_items > 0 do
  {system_items, rest} =
    Enum.split_while(ctx.items, fn
      %ChatMessage{role: :system} -> true
      _ -> false
    end)

  # Drop leading orphaned FunctionCallOutput at the truncation boundary
  truncated_rest =
    rest
    |> Enum.take(-max_items)
    |> drop_leading_orphaned_outputs()

  %{ctx | items: system_items ++ truncated_rest}
end

defp drop_leading_orphaned_outputs(items) do
  call_ids = items
    |> Enum.filter(&match?(%FunctionCall{}, &1))
    |> MapSet.new(& &1.call_id)

  Enum.drop_while(items, fn
    %FunctionCallOutput{call_id: id} -> not MapSet.member?(call_ids, id)
    _ -> false
  end)
end
```

### Constructor with ID generation

```elixir
def new_message(role, content) when is_atom(role) and is_list(content) do
  %ChatMessage{
    id: generate_id(),
    role: role,
    content: content,
    interrupted: false,
    created_at: DateTime.utc_now()
  }
end

defp generate_id do
  :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
end
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `{type, content, timestamp}` tuples (VoiceAgent) | Typed structs with `@type t` | Phase 2 | Pattern matchable, Dialyzer-verifiable |
| `term()` for chat_context in LLM behaviour | `ChatContext.t()` | Phase 2 | Type-safe LLM callback signature |
| No Jason encoding | `defimpl Jason.Encoder` on structs | Phase 2 | Round-trip capable for persistence/logging |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Message-count truncation is sufficient for Phase 2; token counting deferred to Phase 5 | Architecture Patterns | Low — truncation semantics still correct, just less precise |
| A2 | Storing items oldest-first (append) is correct for ChatContext ordering | Architecture Patterns | Medium — would flip truncation logic; easily caught by tests |
| A3 | `System.unique_integer` or `:crypto.strong_rand_bytes` is acceptable for ID generation | Architecture Patterns | Low — either works; UUIDs would be cleaner but no UUID dep exists |
| A4 | Tagged union `String.t() \| map()` for content is sufficient for CHAT-06 multi-modal | Architecture Patterns | Low — can be extended later without breaking the struct shape |

---

## Open Questions

1. **Single file vs. split modules for structs**
   - What we know: Conventions show nested `Config` structs inside parent modules
   - What's unclear: Whether ChatMessage, FunctionCall, FunctionCallOutput should be submodules of ChatContext or top-level under `Livekit.Agents`
   - Recommendation: Nest as `Livekit.Agents.ChatContext.ChatMessage` etc. Matches `LLM.LLMChunk` precedent set in Phase 1.

2. **`to_openai_messages/1` in this phase or Phase 5?**
   - What we know: OpenAI format needs atom roles converted to strings and specific field mapping
   - What's unclear: Whether the conversion helper belongs in ChatContext (coupling) or OpenAI provider (separation)
   - Recommendation: Keep in the OpenAI provider (Phase 5). ChatContext provides `messages/1` which returns `[ChatMessage.t()]`; the provider transforms.

3. **`new_message/2` vs. bare struct creation**
   - What we know: The plan needs consistent ID and timestamp generation
   - What's unclear: Whether to enforce a constructor or allow `%ChatMessage{...}` directly
   - Recommendation: Provide `new_message/2`, `new_function_call/3`, `new_function_call_output/3` constructors. Tests use constructors; struct literal syntax is available for testing convenience.

---

## Environment Availability

Step 2.6: SKIPPED — this phase is purely code/config changes. No external services, databases, CLI tools, or runtimes beyond the project's own Elixir/OTP stack are required.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit (bundled Elixir) |
| Config file | `test/test_helper.exs` |
| Coverage tool | ExCoveralls ~> 0.18 |
| Quick run command | `mix test test/livekit/agents/chat_context_test.exs` |
| Full suite command | `mix coveralls` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CHAT-01 | ChatMessage struct has id, role, content, timestamp fields; role is atom | unit | `mix test test/livekit/agents/chat_context_test.exs --only chat_message` | ❌ Wave 0 |
| CHAT-02 | FunctionCall struct has call_id, name, arguments fields | unit | `mix test test/livekit/agents/chat_context_test.exs --only function_call` | ❌ Wave 0 |
| CHAT-03 | FunctionCallOutput struct has call_id, result, is_error; Jason round-trip | unit | `mix test test/livekit/agents/chat_context_test.exs --only function_call_output` | ❌ Wave 0 |
| CHAT-04 | ChatContext add/truncate/merge/copy operations | unit | `mix test test/livekit/agents/chat_context_test.exs --only chat_context` | ❌ Wave 0 |
| CHAT-05 | truncate/2 never removes system message | unit | `mix test test/livekit/agents/chat_context_test.exs --only truncation` | ❌ Wave 0 |
| CHAT-06 | ChatMessage content accepts list of strings and maps | unit | `mix test test/livekit/agents/chat_context_test.exs --only multimodal` | ❌ Wave 0 |
| TEST-02 | 100% coverage | coverage | `mix coveralls` — check chat_context.ex row | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `mix test test/livekit/agents/chat_context_test.exs`
- **Per wave merge:** `mix coveralls`
- **Phase gate:** `mix coveralls` green with 100% for `lib/livekit/agents/chat_context.ex` before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `test/livekit/agents/chat_context_test.exs` — covers all CHAT-0x requirements
- [ ] No new fixtures or helpers needed (ExUnit + basic assertions sufficient)

---

## Security Domain

Phase 2 is pure data modeling with no I/O, authentication, API calls, or user-supplied data processing. ASVS categories are not applicable.

| ASVS Category | Applies | Reason |
|---------------|---------|--------|
| V2 Authentication | No | No auth logic |
| V3 Session Management | No | No sessions |
| V4 Access Control | No | No access decisions |
| V5 Input Validation | Partial | Role atom validation in constructors (guard clauses on `role in [:system, :user, :assistant, :tool]`) |
| V6 Cryptography | No | ID generation uses `:crypto` for randomness, not cryptographic security |

The only security-adjacent concern: use `String.to_existing_atom/1` (not `String.to_atom/1`) if/when deserializing role strings from external JSON to prevent atom table exhaustion. [ASSUMED — standard Elixir security practice]

---

## Sources

### Primary (HIGH confidence)
- Codebase: `mix.exs`, `mix.lock` — Jason 1.4.4 verified in project
- Codebase: `lib/livekit/agents/llm.ex` — LLM behaviour, term() type annotation, LLMChunk pattern
- Codebase: `lib/livekit/agents/llm/openai.ex` — existing Message struct design, build_messages_for_api pattern
- Codebase: `.planning/codebase/CONVENTIONS.md` — nested structs, @type t, @spec on all public functions
- Codebase: `test/livekit/agents/llm_behaviour_test.exs` — test patterns used in Phase 1

### Secondary (MEDIUM confidence)
- [LiveKit Python agents LLM API docs](https://docs.livekit.io/python/livekit/agents/llm/index.html) — ChatMessage, FunctionCall, FunctionCallOutput fields and truncation semantics

### Tertiary (LOW confidence)
- WebSearch: livekit-agents Python ChatContext GitHub — truncation invariant (system message reinsert) described in search summary; not directly verified from source code

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all deps verified in codebase, no new deps
- Struct design: HIGH — Python reference consulted, existing codebase conventions clear
- Jason encoding pitfalls: HIGH — well-known Elixir/Jason behavior
- Truncation semantics: MEDIUM — Python reference consulted but full source not read line-by-line

**Research date:** 2026-04-14
**Valid until:** 2026-05-14 (stable domain — Jason and ExUnit APIs do not change frequently)
