# Changelog

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
