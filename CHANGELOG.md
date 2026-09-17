# Changelog

## [Unreleased]

### Fixed

- **Egress and Ingress now work at all.** Both clients dialled gRPC and sent
  `authorization: Bearer <key>:<secret>`. A LiveKit server offers neither — it
  serves Twirp over HTTP and expects a signed JWT — so every call through
  either client failed before reaching the service. Both now use the same
  Twirp transport as `Livekit.RoomServiceClient`, with a token carrying
  `roomRecord` and `ingressAdmin` respectively.
- **The protobuf definitions were transcribed by hand and had invented field
  numbers.** `EgressInfo.status` was 4 where LiveKit numbers it 3, `room_name`
  3 where LiveKit has 13, `error` 5 where LiveKit has 9; every storage upload
  type's `bucket` was wrong, as were the oneof tags on three egress request
  types and `SendDataRequest.destination_identities`/`nonce`. Starting an
  egress therefore succeeded on the server and raised `Protobuf.DecodeError`
  reading the reply. The `:proto` compiler generated faithfully from those
  files, so the drift was propagated rather than introduced. `proto/` now
  holds LiveKit's own files, vendored verbatim (`proto/UPSTREAM_VERSION`).
- `Livekit.RoomAgentDispatch` was `name`/`identity`/`init_request`, a shape
  that has never existed upstream, alongside a `Livekit.InitRequest` message
  that LiveKit does not define. It is now `agent_name`/`metadata`.
- `mix livekit start-room-streaming` sent its RTMP URL as a *file* output with
  `file_type: :rtmp`, a member `EncodedFileType` does not have. It now sends
  `stream_outputs`.
- `mix livekit list-egress` iterated the response struct as if it were a list,
  and `stop-egress` passed a bare string where a request struct was expected.

### Added

- `mix livekit.proto.gen` — regenerates `lib/livekit/proto` from `proto/`,
  replacing the `:proto` compiler that ran on every build. That compiler
  globbed `proto/**/*.proto`, so it generated `logger/options.proto` into
  `Logger.Sensitivity` and `Logger.PbExtension` — inside Elixir's own `Logger`
  namespace — and its staleness check looked for the output at a flattened
  path that protoc never wrote, so it regenerated those two on every compile.
  It also required `protoc` on the machine of anyone compiling the package.
  Generated code is committed; regenerating it is a deliberate act, not a
  build step.
- `Livekit.EgressServiceClient`: `start_web_egress/2`,
  `start_participant_egress/2`, `start_track_composite_egress/2`,
  `update_layout/2` and `update_stream/2`, which the service has always
  offered but the client never exposed.
- `Livekit.ProtoFieldNumbersTest` pins the field numbers that were wrong, so a
  hand-edit or a regeneration from the wrong source fails in CI.

### Changed

- **Breaking:** `Livekit.EgressServiceClient.new/3` and
  `Livekit.IngressServiceClient.new/3` return a client struct rather than
  `{:ok, {channel, metadata}}`, matching `RoomServiceClient`. Calls return
  `{:ok, message}` or `{:error, {status, body}}` instead of gRPC results.
- `:grpc` is no longer a dependency. `:gun`, previously arriving transitively
  through it while being used directly by the agents transport, is now a
  direct dependency.

## [0.1.4] - 2025-09-27

### Added

- Support for `name` field during access token creation
- `node_id` parameter support in create room options
- Comprehensive test coverage for create room function options

### Fixed

- Resolved Dialyzer type analysis issues across multiple modules
- Removed Tesla deprecation warnings in room service client
- Improved type specifications in egress service client
- Fixed webhook receiver type handling
- Streamlined mix task implementation

## [0.1.3] - 2025-08-18

### Fixed

- Removed unused `google_protos` and `twirp` dependencies causing module conflicts during mix release
- Resolved issue #3 - duplicate protobuf modules that were conflicting with protobuf ~> 0.14.0

## [0.1.2] - 2025-01-08

### Added

- **Comprehensive Ingress Service Documentation**: Complete interactive Livebook tutorials covering all ingress types
  - `ingress_basic_setup.livemd` - Basic ingress service usage and concepts
  - `ingress_rtmp_streaming.livemd` - Complete RTMP streaming tutorial with OBS/FFmpeg integration
  - `ingress_webrtc_input.livemd` - WebRTC/WHIP streaming setup with browser integration
  - `ingress_file_processing.livemd` - File and URL processing workflows with batch operations
  - `ingress_management.livemd` - Complete lifecycle management with advanced monitoring
  - `ingress_troubleshooting.livemd` - Comprehensive debugging and troubleshooting guide
- Interactive forms and real-time monitoring capabilities in Livebook examples
- Advanced ingress management workflows including batch operations and automated cleanup
- Performance optimization guides and best practices
- Emergency recovery procedures and systematic troubleshooting methodologies

### Changed

- **BREAKING**: Updated `grpc` dependency from `~> 0.7.0` to `~> 0.10.2`
- **BREAKING**: Updated `protobuf` dependency from `~> 0.12.0` to `~> 0.14.0`
- Regenerated all protobuf files with newer protoc-gen-elixir for compatibility
- Updated GRPC service client APIs to use new library syntax
- Modified GRPC credential setup for SSL connections

### Fixed

- Eliminated all Elixir deprecation warnings related to map.field notation
- Fixed FunctionClauseError in GRPC stub method calls
- Resolved Keyword.merge/2 compatibility issues in GRPC client adapters
- Fixed test expectations for exception types with newer GRPC library
- Corrected @describetag usage in performance tests
- Updated service client connection handling for newer GRPC API

### Updated

- README.md with comprehensive ingress service documentation section
- Feature matrix to reflect completed ingress documentation and tutorials
- SDK completion percentage from 60-70% to 70-75%
- Development roadmap to prioritize ingress service implementation

## [0.1.1] - 2025-02-17

### Added

- Configuration system for managing Livekit settings
- Runtime configuration support through environment variables
- Improved error handling for GRPC client operations
- Better token generation with proper grant structure

### Fixed

- Corrected AccessToken grant structure
- Fixed GRPC error handling in room recording
- Improved test coverage and error handling
- Added proper metadata handling in token creation

## [0.1.0] - Initial Release

### Added

- Initial implementation of Livekit client
- Basic room management functionality
- Token generation
- Room recording capabilities
