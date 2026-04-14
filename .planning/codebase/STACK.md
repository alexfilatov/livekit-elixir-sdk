# LiveKit Elixir SDK - Technology Stack

## Language & Runtime

- **Language:** Elixir ~> 1.15
- **Runtime:** BEAM (Erlang/OTP)
- **Build Tool:** Mix
- **Package:** `livekit` v0.1.4 on Hex
- **License:** Apache-2.0

## Core Dependencies

### HTTP & Network
| Dependency | Version | Purpose | Used In |
|-----------|---------|---------|---------|
| `tesla` | ~> 1.7 | HTTP client | `room_service_client.ex`, all agent API clients |
| `hackney` | ~> 1.18 | HTTP adapter for Tesla | Transport layer |
| `mint` | ~> 1.7.1 | Alternative HTTP adapter | Optional |
| `gun` | ~> 2.2.0 | WebSocket & HTTP/2 | gRPC, Deepgram streaming |

### Protocol Buffers & gRPC
| Dependency | Version | Purpose | Used In |
|-----------|---------|---------|---------|
| `protobuf` | ~> 0.14.1 | Protobuf serialization | `lib/livekit/proto/*.pb.ex` |
| `grpc` | ~> 0.10.2 | gRPC framework | `egress_service_client.ex` |

### Authentication & JWT
| Dependency | Version | Purpose | Used In |
|-----------|---------|---------|---------|
| `joken` | ~> 2.6.2 | JWT generation/validation | `access_token.ex` |
| `jose` | ~> 1.11.10 | JOSE crypto operations | HS256 signing |

### JSON & Data
| Dependency | Version | Purpose | Used In |
|-----------|---------|---------|---------|
| `jason` | ~> 1.4.4 | JSON encode/decode | All API clients |
| `inflex` | ~> 2.1.0 | String inflection | camelCase conversion for JWT |

### Streaming & Pipeline
| Dependency | Version | Purpose | Used In |
|-----------|---------|---------|---------|
| `gen_stage` | ~> 1.3.2 | Producer-consumer pattern | gRPC dependency |
| `flow` | ~> 1.2.4 | Data processing pipelines | gRPC dependency |

## Dev Dependencies

| Dependency | Version | Purpose |
|-----------|---------|---------|
| `ex_doc` | ~> 0.29 | Documentation generation |
| `credo` | ~> 1.7 | Code linting |
| `dialyxir` | ~> 1.4 | Static type analysis |
| `bypass` | ~> 2.1.0 | HTTP mocking for tests |
| `mock` | ~> 0.3.0 | Mocking library |
| `excoveralls` | ~> 0.18 | Code coverage |

## Configuration

### Files
- `config/config.exs` — Base config (Joken signer)
- `config/runtime.exs` — Reads `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`
- `config/dev.exs` — Debug logging
- `config/test.exs` — Info logging, custom formatter
- `config/prod.exs` — JSON logging, sensitive header filtering

### Configuration Module
- `lib/livekit/config.ex` — Merges runtime options > app env > env vars
- Type: `%Livekit.Config{url, api_key, api_secret}`

## Custom Build
- Proto compiler: `lib/mix/tasks/compile.proto.ex`
- Compiles `.proto` files to `lib/livekit/proto/*.pb.ex`
