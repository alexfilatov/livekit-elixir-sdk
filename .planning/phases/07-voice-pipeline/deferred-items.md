# Deferred Items — Phase 07: Voice Pipeline

## From Plan 07-02

### Pre-existing callers of old Pipeline mock API

After rewriting `pipeline.ex` to a GenServer, the following files still reference
the old mock API functions (`Pipeline.new/0`, `Pipeline.add_stt_node/3`, etc.).
These produce "undefined or private" compiler warnings but are NOT errors.

These will be resolved when VoiceAgent is updated to use the new Pipeline GenServer API.

**Files:**
- `lib/livekit/agents/voice_agent.ex`
  - `initialize_pipeline/1` (lines ~244–266)
  - `process_audio_frame_internal/2` (line ~285)
  - `cleanup_pipeline/1` (line ~377)
- `lib/mix/tasks/livekit.agents.test.ex`
  - `test_pipeline_init/0` (line ~341)
  - `test_stt_processing/1` (lines ~442, 444)
  - `test_llm_processing/1` (lines ~452, 454)

**Disposition:** Defer to VoiceAgent integration plan (Phase 07 plan 03 or later).
