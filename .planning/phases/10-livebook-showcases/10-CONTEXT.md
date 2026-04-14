# Phase 10: Livebook Showcases - Context

**Gathered:** 2026-04-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Create interactive Livebook (.livemd) scripts that showcase every feature of the LiveKit Elixir Agents framework. Each livebook accepts API keys as inputs (bring-your-own-keys), demonstrates a specific capability, and runs end-to-end. These serve as both documentation and interactive demos.

</domain>

<decisions>
## Implementation Decisions

### Livebook Organization
- **D-01:** One livebook per major feature area (not one giant file)
- **D-02:** Each livebook starts with a "Configuration" section where users enter API keys via Kino.Input
- **D-03:** Livebooks are self-contained — they install deps inline via Mix.install
- **D-04:** Place all livebooks in `examples/livebooks/agents/` directory
- **D-05:** Each livebook has clear section headers, explanatory markdown, and runnable code cells

### Livebooks to Create
- **D-06:** `01_provider_behaviours.livemd` — How to implement custom STT/TTS/LLM/VAD providers
- **D-07:** `02_chat_context.livemd` — Building conversations with ChatContext, messages, function calls
- **D-08:** `03_tool_calling.livemd` — Defining tools, JSON schema generation, execution loop
- **D-09:** `04_deepgram_stt.livemd` — Real speech-to-text with Deepgram API (requires DEEPGRAM_API_KEY)
- **D-10:** `05_openai_llm.livemd` — Chat completions and streaming with OpenAI (requires OPENAI_API_KEY)
- **D-11:** `06_openai_tts.livemd` — Text-to-speech with all voices (requires OPENAI_API_KEY)
- **D-12:** `07_voice_pipeline.livemd` — Full STT→LLM→TTS pipeline with VAD and turn detection (mock providers)
- **D-13:** `08_state_events.livemd` — State machines, events, telemetry, and EventBus pub/sub
- **D-14:** `09_worker_infrastructure.livemd` — Worker supervisor tree, job lifecycle, drain

### API Key Handling
- **D-15:** Use `Kino.Input.text("API Key", type: :password)` for secure key input
- **D-16:** Keys are read via `Kino.Input.read(input)` in the cell that needs them
- **D-17:** Livebooks that don't need API keys (behaviours, chat context, tools, pipeline mock, state, worker) work without any keys
- **D-18:** Livebooks requiring keys (Deepgram, OpenAI LLM, OpenAI TTS) clearly state which keys are needed at the top

### Claude's Discretion
- Exact markdown prose and explanations
- Code cell granularity (how much per cell)
- Visual output formatting with Kino

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `examples/livebooks/voice_agent_interactive.livemd` — existing livebook pattern to follow
- `examples/livebooks/basic_usage.livemd` — shows Mix.install pattern

### Integration Points
- All livebooks use the local livekit package via `Mix.install([{:livekit, path: "."}])`
- Livebooks that need Kino for inputs: `Mix.install([{:livekit, path: "."}, {:kino, "~> 0.14"}])`

</code_context>

<specifics>
## Specific Ideas

- Each livebook should be a tutorial — explain WHY, not just show code
- Include expected output descriptions so users know what to expect
- For API-key livebooks, include a "Mock Mode" fallback section that works without keys

</specifics>

<deferred>
## Deferred Ideas

None.

</deferred>

---

*Phase: 10-livebook-showcases*
*Context gathered: 2026-04-14*
