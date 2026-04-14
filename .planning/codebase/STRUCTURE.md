# LiveKit Elixir SDK - Directory Structure

```
livekit/
├── lib/
│   ├── livekit.ex                          # Root module, version, docs
│   ├── livekit/
│   │   ├── access_token.ex                 # JWT generation (builder pattern)
│   │   ├── config.ex                       # SDK configuration
│   │   ├── grants.ex                       # Token permission grants
│   │   ├── token_verifier.ex               # JWT verification
│   │   ├── room_service_client.ex          # Room API (Twirp/HTTP+Protobuf)
│   │   ├── egress_service_client.ex        # Egress API (gRPC)
│   │   ├── ingress_service_client.ex       # Ingress API
│   │   ├── webhook_receiver.ex             # Webhook validation
│   │   ├── utils.ex                        # Utility functions
│   │   ├── test_formatter.ex               # Test log formatter
│   │   │
│   │   ├── agents/                         # Agent framework
│   │   │   ├── worker.ex                   # Job dispatcher (GenServer, 590 lines)
│   │   │   ├── agent_session.ex            # Room connection (GenServer, 446 lines)
│   │   │   ├── voice_agent.ex              # Conversation orchestrator (GenServer, 379 lines)
│   │   │   ├── pipeline.ex                 # STT->LLM->TTS pipeline (331 lines)
│   │   │   ├── audio_frame.ex              # Audio data struct (372 lines)
│   │   │   ├── job_context.ex              # Job context struct (174 lines)
│   │   │   ├── stt/
│   │   │   │   └── deepgram.ex             # Deepgram STT provider (GenServer, 380 lines)
│   │   │   ├── llm/
│   │   │   │   └── openai.ex               # OpenAI LLM provider (GenServer, 383 lines)
│   │   │   └── tts/
│   │   │       └── openai.ex               # OpenAI TTS provider (GenServer, 340 lines)
│   │   │
│   │   └── proto/                          # Generated Protobuf modules
│   │       ├── livekit_models.pb.ex        # Room, Participant, Track types
│   │       ├── livekit_room.pb.ex          # Room service RPC
│   │       ├── livekit_egress.pb.ex        # Egress operations
│   │       ├── livekit_ingress.pb.ex       # Ingress operations
│   │       ├── livekit_webhook.pb.ex       # Webhook events
│   │       └── livekit_agent_dispatch.pb.ex # Agent dispatch messages
│   │
│   └── mix/tasks/
│       ├── compile.proto.ex                # Custom proto compiler
│       ├── livekit.agents.ex               # Task router (subcommands)
│       ├── livekit.agents.dev.ex           # Dev server with hot reload (417 lines)
│       ├── livekit.agents.start.ex         # Production launcher (404 lines)
│       └── livekit.agents.test.ex          # Agent test runner (481 lines)
│
├── proto/                                  # Protobuf source definitions
│   ├── livekit_models.proto
│   ├── livekit_room.proto
│   ├── livekit_egress.proto
│   ├── livekit_ingress.proto
│   ├── livekit_webhook.proto
│   └── livekit_agent_dispatch.proto
│
├── config/
│   ├── config.exs                          # Base config (Joken signer)
│   ├── runtime.exs                         # Runtime env vars
│   ├── dev.exs                             # Debug logging
│   ├── test.exs                            # Test config
│   └── prod.exs                            # Production logging
│
├── test/
│   ├── test_helper.exs                     # ExUnit setup
│   ├── livekit_test.exs                    # Root module tests
│   ├── livekit_task_test.exs               # Mix task tests
│   └── livekit/
│       ├── access_token_test.exs           # JWT tests
│       ├── config_test.exs                 # Config tests
│       ├── grants_test.exs                 # Grants tests
│       ├── room_service_client_test.exs    # Room API tests (Bypass)
│       ├── token_verifier_test.exs         # Token verification tests
│       ├── webhook_receiver_test.exs       # Webhook tests (Mock)
│       ├── webhook_integration_test.exs    # Webhook integration
│       ├── ingress_cli_test.exs            # Ingress tests
│       └── agents/
│           ├── voice_agent_test.exs        # VoiceAgent unit tests
│           ├── audio_frame_test.exs        # AudioFrame unit tests
│           └── integration_test.exs        # End-to-end (@moduletag :integration)
│
├── examples/
│   ├── token_generation.exs
│   ├── room_management.exs
│   ├── participant_management.exs
│   ├── livebooks/
│   │   ├── basic_usage.livemd
│   │   ├── advanced_usage.livemd
│   │   ├── voice_agent_interactive.livemd
│   │   └── ingress_*.livemd (6 notebooks)
│   └── docker/
│       ├── docker-compose.yml
│       └── livekit.yaml
│
├── docs/implementation/                    # Implementation plans
│   ├── IMPLEMENTATION_PLAN.md
│   ├── 01_ingress_service.md
│   └── ... (6 plan documents)
│
├── mix.exs                                 # Project definition
├── mix.lock                                # Dependency lock
├── .formatter.exs                          # Code formatter config
├── .credo.exs                              # Linter config
└── .github/workflows/ci.yml               # CI pipeline

## Naming Conventions

- **Modules**: `Livekit.Agents.STT.Deepgram` (PascalCase, dot-separated)
- **Files**: `voice_agent.ex` (snake_case matching module name)
- **Functions**: `get_status/1`, `process_audio_frame/2` (snake_case)
- **Variables**: `audio_data`, `room_name` (descriptive snake_case)
- **Constants**: Module attributes `@version "0.1.4"`
- **Providers**: `Livekit.Agents.{STT,LLM,TTS}.ProviderName`
- **Mix tasks**: `Mix.Tasks.Livekit.Agents.Start` -> `mix livekit.agents.start`
```
