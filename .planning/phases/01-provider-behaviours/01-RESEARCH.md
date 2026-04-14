# Phase 1: Provider Behaviours - Research

**Researched:** 2026-04-14
**Domain:** Elixir behaviour modules, OTP message-passing contracts, provider plugin architecture
**Confidence:** HIGH

## Summary

This phase defines four Elixir behaviour modules — `Livekit.Agents.STT`, `Livekit.Agents.TTS`,
`Livekit.Agents.LLM`, and `Livekit.Agents.VAD` — plus three event structs (`SpeechEvent`,
`LLMChunk`, `VADEvent`) and a shared error type enumeration. All user decisions from CONTEXT.md
are well-specified; the main open design questions are in Claude's Discretion territory: whether
streaming callbacks are `@optional_callbacks`, how to document them, and whether a `__using__`
macro reduces boilerplate in implementing modules.

The existing provider mocks (Deepgram STT, OpenAI LLM, OpenAI TTS) already follow the codebase
GenServer + nested Config/State struct pattern. This phase does NOT modify those modules — it only
creates the behaviour modules they will later `@behaviour`-declare. The Pipeline module currently
calls providers by raw GenServer message names (`{:process_audio, frame}`, `{:process_text, text}`,
`{:synthesize_text, text}`) with no behaviour contract enforced. After this phase, the Pipeline and
future providers have a verified contract to code against.

Test coverage requirement (TEST-01, 100%) is achievable with a small conformance-test suite:
a minimal "stub" module that implements each behaviour is compiled and exercised in ExUnit.

**Primary recommendation:** Define each behaviour as a pure module (no `use GenServer`) with
`@callback` declarations, typespecs, and `@doc` examples. Use `@optional_callbacks` for the
`stream/*` callbacks so batch-only providers are valid. Provide a `__using__` macro that injects
`@behaviour __MODULE__` and a default `validate_config/1` that returns `:ok`.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** STT behaviour defines `transcribe/2` (batch: audio binary + opts -> transcript) and `stream/1` (returns a streaming process ref that sends `{:speech_event, event}` messages)
- **D-02:** TTS behaviour defines `synthesize/2` (batch: text + opts -> audio binary) and `stream/1` (returns streaming process that accepts text chunks and emits audio frames)
- **D-03:** LLM behaviour defines `chat/2` (chat_context + opts -> chat_message) and `stream/2` (chat_context + opts -> streaming process emitting text chunks)
- **D-04:** VAD behaviour defines `stream/1` (returns process that accepts audio frames and emits `{:vad_event, event}` messages for speech start/end)
- **D-05:** Follow the Python agents pattern: batch methods are synchronous request/response, stream methods return a process that emits events asynchronously
- **D-06:** Each behaviour requires a `capabilities/0` callback returning `%{atom => boolean | term}`
- **D-07:** STT capabilities: `streaming`, `interim_results`, `diarization`, `languages`
- **D-08:** TTS capabilities: `streaming`, `voices`, `audio_formats`, `word_timing`
- **D-09:** LLM capabilities: `streaming`, `tool_calling`, `vision`, `max_context_tokens`
- **D-10:** VAD capabilities: `realtime`, `speech_probability`
- **D-11:** Batch callbacks return `{:ok, result}` or `{:error, reason}` — follows existing codebase convention
- **D-12:** Streaming processes send `{:error, reason}` message to subscriber on failure
- **D-13:** Define common error types: `:api_error`, `:timeout`, `:invalid_config`, `:rate_limited`
- **D-14:** Keep existing `{module, config_map}` tuple pattern from VoiceAgent.Config — providers receive config as a map in their init
- **D-15:** Each behaviour optionally defines `validate_config/1` callback (default impl returns `:ok`)
- **D-16:** Each behaviour defines `@type config :: map()` for documentation
- **D-17:** Define `SpeechEvent` struct: `%{type: :start | :interim | :final | :end, text: String.t(), confidence: float(), language: String.t()}`
- **D-18:** Define `VADEvent` struct: `%{type: :speech_start | :speech_end | :inference, probability: float(), frames: [AudioFrame.t()]}`
- **D-19:** Define `LLMChunk` struct for streaming: `%{type: :text | :tool_call | :done, content: term()}`

### Claude's Discretion

- Exact typespec syntax and optional callback organization
- Whether to use `@optional_callbacks` for streaming or make all callbacks required
- Helper macros or `__using__` hooks for common boilerplate

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| BEHV-01 | Define `Livekit.Agents.STT` behaviour with callbacks for streaming and batch transcription | D-01, D-07, D-11–D-16 + typespec patterns below |
| BEHV-02 | Define `Livekit.Agents.TTS` behaviour with callbacks for streaming and batch synthesis | D-02, D-08, D-11–D-16 + typespec patterns below |
| BEHV-03 | Define `Livekit.Agents.LLM` behaviour with callbacks for chat completion and streaming | D-03, D-09, D-11–D-16 + typespec patterns below |
| BEHV-04 | Define `Livekit.Agents.VAD` behaviour with callbacks for voice activity detection | D-04, D-10, D-11–D-16 + typespec patterns below |
| BEHV-05 | Each behaviour defines capability introspection | D-06–D-10 + capabilities/0 callback pattern below |
| TEST-01 | 100% test coverage for all new behaviour modules | Conformance-stub test pattern below |
</phase_requirements>

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Elixir `@behaviour` / `@callback` | Built-in | Define behaviour contracts | Language primitive — no extra dep |
| `@optional_callbacks` | Built-in | Mark streaming as optional | Allows batch-only providers to be valid |
| ExUnit | Built-in | Behaviour conformance tests | Already in project |

No new runtime dependencies are needed. [VERIFIED: mix.exs in codebase]

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `excoveralls` | ~> 0.18 | Enforce 100% coverage | Already in mix.exs — run `mix coveralls` |
| `credo` | ~> 1.7 strict | Lint — catches missing @moduledoc | Already configured |
| `dialyxir` | ~> 1.4 | Typecheck specs | Already configured — run after defining types |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `@behaviour` module | Protocol | Protocols dispatch on data type, not module choice. Behaviours fit provider-injection pattern (`{module, config}`) better — protocols don't have `@optional_callbacks` |
| Separate event files | Inline structs in behaviour module | Separate files are cleaner for importing (`alias Livekit.Agents.STT.SpeechEvent`) |

**Installation:** No new packages required. [VERIFIED: mix.exs]

---

## Architecture Patterns

### Recommended File Structure

```
lib/livekit/agents/
├── stt.ex                 # Livekit.Agents.STT behaviour + SpeechEvent struct
├── tts.ex                 # Livekit.Agents.TTS behaviour
├── llm.ex                 # Livekit.Agents.LLM behaviour + LLMChunk struct
├── vad.ex                 # Livekit.Agents.VAD behaviour + VADEvent struct
└── [existing files unchanged]

test/livekit/agents/
├── stt_behaviour_test.exs
├── tts_behaviour_test.exs
├── llm_behaviour_test.exs
└── vad_behaviour_test.exs
```

Event structs co-located with their behaviour module: `SpeechEvent` in `stt.ex`,
`LLMChunk` in `llm.ex`, `VADEvent` in `vad.ex`. This mirrors Phoenix context convention
and avoids an extra layer of aliasing. [ASSUMED — no explicit project rule; consistent with
the pattern of `LLM.OpenAI.Message` being defined inside `llm/openai.ex`]

### Pattern 1: Behaviour Module with `__using__` Macro

**What:** A behaviour module defines `@callback` declarations AND a `__using__` macro that
injects `@behaviour` and a default `validate_config/1`.

**When to use:** Any module that will be `use`d by implementing providers. This reduces
boilerplate: each provider only needs `use Livekit.Agents.STT` instead of both
`@behaviour Livekit.Agents.STT` and a copy of the default `validate_config/1`.

**Example:**

```elixir
# Source: Elixir official docs — https://hexdocs.pm/elixir/Module.html#module-behaviour
defmodule Livekit.Agents.STT do
  @moduledoc """
  Behaviour contract for Speech-to-Text providers.

  ## Implementing a provider

      defmodule MySTT do
        use Livekit.Agents.STT

        @impl true
        def transcribe(audio_binary, opts) do
          # ...
          {:ok, %Livekit.Agents.STT.SpeechEvent{...}}
        end

        @impl true
        def capabilities do
          %{streaming: false, interim_results: false, diarization: false, languages: ["en"]}
        end
      end
  """

  @type config :: map()
  @type error_reason :: :api_error | :timeout | :invalid_config | :rate_limited | term()

  # Batch: audio binary + opts -> speech event (final transcript)
  @callback transcribe(audio :: binary(), opts :: keyword()) ::
              {:ok, __MODULE__.SpeechEvent.t()} | {:error, error_reason()}

  # Streaming: returns pid of a process that accepts audio frames
  # and sends {:speech_event, SpeechEvent.t()} to the caller
  @callback stream(config :: config()) :: {:ok, pid()} | {:error, error_reason()}

  # Capability introspection
  @callback capabilities() :: %{
    streaming: boolean(),
    interim_results: boolean(),
    diarization: boolean(),
    languages: [String.t()]
  }

  # Optional — providers may implement for config validation
  @callback validate_config(config :: config()) :: :ok | {:error, error_reason()}

  @optional_callbacks [stream: 1, validate_config: 1]

  defmacro __using__(_opts) do
    quote do
      @behaviour Livekit.Agents.STT

      @impl true
      def validate_config(_config), do: :ok

      defoverridable validate_config: 1
    end
  end
end
```

[CITED: https://hexdocs.pm/elixir/Module.html#module-behaviour]
[CITED: https://hexdocs.pm/elixir/behaviours.html]

### Pattern 2: Event Struct as Nested Module

**What:** Define event structs as submodules of their behaviour, e.g., `Livekit.Agents.STT.SpeechEvent`.

**When to use:** Always — enables `alias Livekit.Agents.STT.SpeechEvent` in provider modules
and keeps the struct tightly coupled to the contract it belongs to.

**Example:**

```elixir
defmodule Livekit.Agents.STT.SpeechEvent do
  @moduledoc """
  Event emitted by STT streaming processes.

  Sent to subscriber as `{:speech_event, %SpeechEvent{}}`.
  """

  @type event_type :: :start | :interim | :final | :end

  @type t :: %__MODULE__{
    type: event_type(),
    text: String.t(),
    confidence: float(),
    language: String.t()
  }

  defstruct [
    :type,
    text: "",
    confidence: 0.0,
    language: "en"
  ]
end
```

[ASSUMED — struct placement is discretionary; nested module is idiomatic for companion types]

### Pattern 3: Conformance Test with Stub Implementation

**What:** Each behaviour test file defines a minimal stub that `use`s the behaviour and
checks all required callbacks compile and return correct shapes.

**When to use:** Required for 100% test coverage (TEST-01).

**Example:**

```elixir
# test/livekit/agents/stt_behaviour_test.exs
defmodule Livekit.Agents.STTTest do
  use ExUnit.Case, async: true

  alias Livekit.Agents.STT
  alias Livekit.Agents.STT.SpeechEvent

  # Minimal stub implementing required callbacks
  defmodule StubSTT do
    use Livekit.Agents.STT

    @impl true
    def transcribe(_audio, _opts) do
      {:ok, %SpeechEvent{type: :final, text: "hello", confidence: 0.99, language: "en"}}
    end

    @impl true
    def capabilities do
      %{streaming: false, interim_results: false, diarization: false, languages: ["en"]}
    end
  end

  test "stub implements behaviour without errors" do
    assert {:ok, event} = StubSTT.transcribe(<<1, 2, 3>>, [])
    assert event.type == :final
    assert event.text == "hello"
  end

  test "capabilities/0 returns required keys" do
    caps = StubSTT.capabilities()
    assert Map.has_key?(caps, :streaming)
    assert Map.has_key?(caps, :interim_results)
    assert Map.has_key?(caps, :diarization)
    assert Map.has_key?(caps, :languages)
  end

  test "default validate_config returns :ok" do
    assert :ok == StubSTT.validate_config(%{api_key: "test"})
  end
end
```

[VERIFIED: ExUnit `use ExUnit.Case` pattern — matches test/livekit/agents/audio_frame_test.exs in codebase]

### Pattern 4: `@optional_callbacks` for Streaming

**What:** Declare `stream/1` (and `stream/2` for LLM) as `@optional_callbacks`. Providers that
only support batch are valid implementors.

**Why this matters for the Pipeline:** The Pipeline must check `function_exported?(module, :stream, 1)`
before calling streaming paths. This is the standard Elixir idiom for optional callback detection.
[CITED: https://hexdocs.pm/elixir/Module.html#optional_callbacks/1]

```elixir
@optional_callbacks [stream: 1, validate_config: 1]

# In Pipeline (Phase 7), safe check:
if function_exported?(stt_module, :stream, 1) do
  stt_module.stream(config)
else
  {:error, :streaming_not_supported}
end
```

### Anti-Patterns to Avoid

- **Behaviours that `use GenServer`:** Keep behaviour modules as pure contracts with no process state. Provider implementations `use GenServer`; the behaviour module does not.
- **Overspecifying callback signatures:** D-03 says `chat/2` takes a `chat_context` — but `ChatContext` is defined in Phase 2. For Phase 1, type the first arg as `list()` or `term()` to avoid a compile-time dependency on a not-yet-existing module. Update the typespec in Phase 2.
- **Putting behaviour + GenServer in the same file:** The pattern `use Livekit.Agents.STT` in a provider means the provider module declares its own `use GenServer` independently. Mixing them causes confusion about which callbacks are GenServer callbacks vs behaviour callbacks.
- **Missing `@impl true`:** Credo strict mode will flag this. All behaviour callbacks in implementing modules must have `@impl true`. Enforce in the `__using__` template shown in `@doc` examples.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Optional default implementations | Custom macro system | `defoverridable` + `__using__` macro | Built-in, Credo-safe, supported pattern |
| Behaviour conformance checks | Runtime introspection | Compile-time `@behaviour` + `@impl true` | Compiler flags non-conforming modules |
| Streaming process communication | Custom protocol | Plain `send/2` with tagged tuples | OTP idiom, no extra dep, matches Python agents' message-passing style |
| Config validation dispatch | Dynamic dispatch table | `@optional_callbacks validate_config/1` + `function_exported?/3` | Elixir built-in, no boilerplate |

**Key insight:** Elixir behaviours with `@optional_callbacks` and `defoverridable` already solve everything needed here. No custom macro or registry system is warranted.

---

## Common Pitfalls

### Pitfall 1: `chat_context` Type Forward Reference

**What goes wrong:** Defining `@callback chat/2` with a `ChatContext.t()` type when `ChatContext` doesn't exist yet (Phase 2).

**Why it happens:** Phase sequencing — behaviours come before the data types they reference.

**How to avoid:** Use `term()` or `list()` as a placeholder type for the first argument of `chat/2` in Phase 1. Add a `@type chat_context :: term()` alias in the behaviour module and update it in Phase 2 when `ChatContext` is defined.

**Warning signs:** `** (CompileError) undefined module Livekit.Agents.ChatContext` during `mix compile`.

### Pitfall 2: Streaming PID Lifecycle Not Specified

**What goes wrong:** Callers don't know who owns the streaming process or when it terminates. Leaked processes cause memory issues.

**Why it happens:** The behaviour contract doesn't say "streaming process exits after sending `{:speech_event, %{type: :end}}`."

**How to avoid:** Document in `@doc` for `stream/1` that the returned process sends events to `self()` (the caller's PID at invocation time) and exits normally after sending the terminal event (`:end` for STT, `:done` chunk for LLM). Make this explicit in the `SpeechEvent` and `LLMChunk` struct docs.

**Warning signs:** Streaming tests that never complete, processes accumulating in observer.

### Pitfall 3: Credo Strict Mode — Missing `@moduledoc`

**What goes wrong:** Credo strict `ModuleDoc` check fails for nested struct modules (e.g., `SpeechEvent`) that omit `@moduledoc`.

**Why it happens:** Credo strict requires `@moduledoc` on every public module, including nested ones.

**How to avoid:** Add `@moduledoc """..."""` to every nested struct module. `@moduledoc false` is also valid (suppresses the doc) but less useful for a public API.

**Warning signs:** `mix credo --strict` output: `Credo.Check.Readability.ModuleDoc`.

### Pitfall 4: `@optional_callbacks` Must List Exact Arity

**What goes wrong:** `@optional_callbacks [stream]` (without arity) compiles but does not actually mark the callback as optional in older Elixir versions.

**Why it happens:** `@optional_callbacks` requires the `name: arity` keyword format.

**How to avoid:** Always use `@optional_callbacks [stream: 1, validate_config: 1]`.
[CITED: https://hexdocs.pm/elixir/Module.html#optional_callbacks/1]

### Pitfall 5: Dialyzer Warning on `@optional_callbacks` + `defoverridable`

**What goes wrong:** Dialyzer may warn that `validate_config/1` defined via `defoverridable` has no spec.

**Why it happens:** The spec lives on the `@callback` but the default implementation in `__using__` has no separate `@spec`.

**How to avoid:** The `@callback` spec applies — no separate `@spec` needed. If Dialyzer still warns, add to `dialyzer.ignore-warnings`.

---

## Code Examples

Verified patterns from official sources and existing codebase:

### Full STT Behaviour Skeleton

```elixir
# lib/livekit/agents/stt.ex
defmodule Livekit.Agents.STT do
  @moduledoc """
  Behaviour contract for Speech-to-Text providers.

  ## Batch usage

      {:ok, event} = MySTT.transcribe(audio_binary, language: "en")

  ## Streaming usage

      {:ok, stream_pid} = MySTT.stream(config)
      # stream_pid sends: {:speech_event, %Livekit.Agents.STT.SpeechEvent{}}
      # Terminal event has type: :end
  """

  alias Livekit.Agents.STT.SpeechEvent

  @type config :: map()
  @type error_reason :: :api_error | :timeout | :invalid_config | :rate_limited | term()

  @callback transcribe(audio :: binary(), opts :: keyword()) ::
              {:ok, SpeechEvent.t()} | {:error, error_reason()}

  @callback stream(config :: config()) :: {:ok, pid()} | {:error, error_reason()}

  @callback capabilities() :: %{
              streaming: boolean(),
              interim_results: boolean(),
              diarization: boolean(),
              languages: [String.t()]
            }

  @callback validate_config(config :: config()) :: :ok | {:error, error_reason()}

  @optional_callbacks [stream: 1, validate_config: 1]

  defmacro __using__(_opts) do
    quote do
      @behaviour Livekit.Agents.STT

      @impl Livekit.Agents.STT
      def validate_config(_config), do: :ok

      defoverridable validate_config: 1
    end
  end
end

defmodule Livekit.Agents.STT.SpeechEvent do
  @moduledoc """
  Event emitted by an STT streaming process.

  The streaming process sends `{:speech_event, %SpeechEvent{}}` to the
  subscriber process. A `:end` type event signals the stream is complete.
  """

  @type event_type :: :start | :interim | :final | :end

  @type t :: %__MODULE__{
          type: event_type(),
          text: String.t(),
          confidence: float(),
          language: String.t()
        }

  defstruct [
    :type,
    text: "",
    confidence: 0.0,
    language: "en"
  ]
end
```

### Full LLM Behaviour Skeleton (with chat_context placeholder)

```elixir
# lib/livekit/agents/llm.ex
defmodule Livekit.Agents.LLM do
  @moduledoc """
  Behaviour contract for Large Language Model providers.

  `chat_context` is typed as `term()` in Phase 1. It will be tightened to
  `Livekit.Agents.ChatContext.t()` in Phase 2.
  """

  alias Livekit.Agents.LLM.LLMChunk

  @type config :: map()
  @type chat_context :: term()  # Updated to ChatContext.t() in Phase 2
  @type chat_message :: %{role: atom(), content: String.t()}
  @type error_reason :: :api_error | :timeout | :invalid_config | :rate_limited | term()

  @callback chat(chat_context :: chat_context(), opts :: keyword()) ::
              {:ok, chat_message()} | {:error, error_reason()}

  @callback stream(chat_context :: chat_context(), opts :: keyword()) ::
              {:ok, pid()} | {:error, error_reason()}

  @callback capabilities() :: %{
              streaming: boolean(),
              tool_calling: boolean(),
              vision: boolean(),
              max_context_tokens: pos_integer() | nil
            }

  @callback validate_config(config :: config()) :: :ok | {:error, error_reason()}

  @optional_callbacks [stream: 2, validate_config: 1]

  defmacro __using__(_opts) do
    quote do
      @behaviour Livekit.Agents.LLM

      @impl Livekit.Agents.LLM
      def validate_config(_config), do: :ok

      defoverridable validate_config: 1
    end
  end
end

defmodule Livekit.Agents.LLM.LLMChunk do
  @moduledoc """
  A streaming chunk emitted by an LLM streaming process.

  Sent as `{:llm_chunk, %LLMChunk{}}`. A `:done` type chunk signals completion.
  """

  @type chunk_type :: :text | :tool_call | :done

  @type t :: %__MODULE__{
          type: chunk_type(),
          content: term()
        }

  defstruct [:type, content: nil]
end
```

### VAD Behaviour Skeleton

```elixir
# lib/livekit/agents/vad.ex
defmodule Livekit.Agents.VAD do
  @moduledoc """
  Behaviour contract for Voice Activity Detection providers.

  The streaming process accepts audio frames (sent via `send/2`) and emits
  `{:vad_event, %Livekit.Agents.VAD.VADEvent{}}` to the subscriber.
  """

  alias Livekit.Agents.VAD.VADEvent

  @type config :: map()
  @type error_reason :: :api_error | :timeout | :invalid_config | :rate_limited | term()

  # VAD is streaming-only by design (D-04)
  @callback stream(config :: config()) :: {:ok, pid()} | {:error, error_reason()}

  @callback capabilities() :: %{
              realtime: boolean(),
              speech_probability: boolean()
            }

  @callback validate_config(config :: config()) :: :ok | {:error, error_reason()}

  @optional_callbacks [validate_config: 1]

  defmacro __using__(_opts) do
    quote do
      @behaviour Livekit.Agents.VAD

      @impl Livekit.Agents.VAD
      def validate_config(_config), do: :ok

      defoverridable validate_config: 1
    end
  end
end

defmodule Livekit.Agents.VAD.VADEvent do
  @moduledoc """
  Event emitted by a VAD streaming process.

  Sent as `{:vad_event, %VADEvent{}}`.
  """

  alias Livekit.Agents.AudioFrame

  @type event_type :: :speech_start | :speech_end | :inference

  @type t :: %__MODULE__{
          type: event_type(),
          probability: float(),
          frames: [AudioFrame.t()]
        }

  defstruct [
    :type,
    probability: 0.0,
    frames: []
  ]
end
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Raw GenServer.call with ad-hoc messages | `@behaviour` + `@callback` contracts | This phase | Pipeline can call any conforming module without knowing internals |
| Inline mock responses in Pipeline | Stub modules implementing behaviour | This phase | Tests verify contracts, not Pipeline internals |

**Note on `@impl true` in Elixir 1.15+:** `@impl true` on behaviour callbacks in implementing modules is strongly recommended and Credo-enforced here. Elixir 1.15+ emits a compiler warning if a function matches a callback name but `@impl` is missing. [CITED: https://hexdocs.pm/elixir/1.15/Module.html#module-impl]

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Event struct files co-located in the same `.ex` file as their behaviour (e.g., `SpeechEvent` in `stt.ex`) | Architecture Patterns | Low — if project convention prefers separate files, each struct gets its own file; no behaviour logic changes |
| A2 | `chat_context` typed as `term()` in Phase 1 is accepted by dialyxir without error | Code Examples | Low — worst case add to `dialyzer.ignore-warnings` or use `any()` |
| A3 | Streaming processes use `send(subscriber_pid, {:speech_event, event})` rather than a GenStage producer | Code Examples | Medium — GenStage was mentioned in STATE.md for the Pipeline (Phase 7), but stream/1 returning a plain pid is cleaner for the behaviour contract; GenStage can be used internally by providers |

---

## Open Questions

1. **Streaming subscriber PID — caller or explicit argument?**
   - What we know: D-01 says `stream/1` returns a process ref that sends to subscriber. Python agents pass subscriber at construction. Elixir convention would be `self()` at call time.
   - What's unclear: Should `stream/1` implicitly use `self()` or should the callback be `stream/2` with explicit `subscriber_pid`?
   - Recommendation: Use `self()` implicitly (single-arg) — simpler API, matches D-01 literal spec. Document that providers must capture caller PID at `stream/1` invocation via `subscriber = self()`.

2. **Error type module — separate or inline?**
   - What we know: D-13 lists `:api_error | :timeout | :invalid_config | :rate_limited`. These are plain atoms, no struct needed.
   - What's unclear: Whether a shared `Livekit.Agents.ProviderError` struct (with reason + message + metadata) would be better than bare atoms.
   - Recommendation: Keep as bare atoms for Phase 1 — simpler, matches existing codebase error convention. Structured error types can be added in Phase 4+ when real providers surface richer error data.

---

## Environment Availability

Step 2.6: SKIPPED (no external dependencies — this phase is pure Elixir code creation with no runtime external tools)

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit (built-in, no version) |
| Config file | `test/test_helper.exs` (exists) |
| Quick run command | `mix test test/livekit/agents/stt_behaviour_test.exs` |
| Full suite command | `mix test` |
| Coverage command | `mix coveralls` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| BEHV-01 | STT behaviour compiles, required callbacks enforced | unit | `mix test test/livekit/agents/stt_behaviour_test.exs` | ❌ Wave 0 |
| BEHV-02 | TTS behaviour compiles, required callbacks enforced | unit | `mix test test/livekit/agents/tts_behaviour_test.exs` | ❌ Wave 0 |
| BEHV-03 | LLM behaviour compiles, required callbacks enforced | unit | `mix test test/livekit/agents/llm_behaviour_test.exs` | ❌ Wave 0 |
| BEHV-04 | VAD behaviour compiles, required callbacks enforced | unit | `mix test test/livekit/agents/vad_behaviour_test.exs` | ❌ Wave 0 |
| BEHV-05 | `capabilities/0` returns map with all required keys per provider type | unit | same test files | ❌ Wave 0 |
| TEST-01 | 100% coverage for behaviour modules | coverage | `mix coveralls` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `mix test test/livekit/agents/` (agents tests only)
- **Per wave merge:** `mix test`
- **Phase gate:** `mix coveralls` green (100% for new files) before marking phase complete

### Wave 0 Gaps

- [ ] `test/livekit/agents/stt_behaviour_test.exs` — covers BEHV-01, BEHV-05
- [ ] `test/livekit/agents/tts_behaviour_test.exs` — covers BEHV-02, BEHV-05
- [ ] `test/livekit/agents/llm_behaviour_test.exs` — covers BEHV-03, BEHV-05
- [ ] `test/livekit/agents/vad_behaviour_test.exs` — covers BEHV-04, BEHV-05

No framework installation needed — ExUnit and all dependencies already in mix.exs.

---

## Security Domain

This phase defines pure Elixir contracts (no HTTP calls, no secrets, no auth). ASVS categories V2, V3, V4, V6 do not apply.

| ASVS Category | Applies | Notes |
|---------------|---------|-------|
| V5 Input Validation | Minimal | `validate_config/1` callback validates provider config maps. No user-facing input in this phase. |
| All others | No | Pure behaviour module definitions only |

---

## Project Constraints (from CLAUDE.md)

Directives the planner must verify compliance with:

| Directive | Impact on This Phase |
|-----------|---------------------|
| Fix all compiler warnings in files touched | Behaviour modules must compile cleanly — no unused variables, no missing `@impl` annotations |
| Never commit without explicit user approval | Not a code constraint, but planner should not include commit steps in automated tasks |
| `@moduledoc` required (Credo strict) | Every public module including event structs needs `@moduledoc` |
| `@doc` on all public functions, `@spec` on all public functions | All callbacks need `@spec`-equivalent `@callback` type signatures; `__using__` macro needs `@doc` |
| No real API calls in tests | N/A — this phase creates no HTTP clients |
| `mix format` + `mix credo --strict` must pass | All new `.ex` files must be formatted and Credo-clean before marking tasks done |
| 100% test coverage via ExCoveralls | TEST-01 requirement; must verify with `mix coveralls` |
| Tech stack: Elixir ~> 1.15, OTP | Behaviours are built-in — no constraint issue |
| Must not break existing core SDK | New files only — existing modules untouched in this phase |

---

## Sources

### Primary (HIGH confidence)

- [VERIFIED: Elixir official docs] https://hexdocs.pm/elixir/behaviours.html — `@behaviour`, `@callback`, `@optional_callbacks`
- [VERIFIED: Elixir Module docs] https://hexdocs.pm/elixir/Module.html#optional_callbacks/1 — arity-qualified optional callbacks format
- [VERIFIED: codebase] `lib/livekit/agents/stt/deepgram.ex`, `llm/openai.ex`, `tts/openai.ex` — existing API surface to align with
- [VERIFIED: codebase] `mix.exs` — confirmed no new deps needed
- [VERIFIED: codebase] `test/livekit/agents/audio_frame_test.exs` — confirmed ExUnit async test pattern
- [VERIFIED: codebase] `.credo.exs` — strict mode confirmed

### Secondary (MEDIUM confidence)

- [CITED: https://hexdocs.pm/elixir/1.15/Module.html#module-impl] `@impl true` requirement in Elixir 1.15+ for callback implementations

### Tertiary (LOW confidence)

- [ASSUMED] Python agents STT/TTS/LLM/VAD interface patterns (subscriber PID conventions) — not directly verified against github.com/livekit/agents source in this session

---

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH — no new deps, all built-in Elixir primitives
- Architecture: HIGH — derived directly from codebase patterns and locked CONTEXT.md decisions
- Pitfalls: HIGH — concrete compiler/Credo/dialyzer issues from known Elixir behaviour gotchas
- Event struct placement: MEDIUM — discretionary, consistent with codebase style

**Research date:** 2026-04-14
**Valid until:** 2026-05-14 (stable Elixir built-ins; no fast-moving ecosystem)
