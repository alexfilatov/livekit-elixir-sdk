# Ingress Service Implementation

## Overview

The Ingress Service enables bringing external streams into LiveKit rooms. This includes RTMP streams, WebRTC ingress, and file-based input sources.

## Technical Specifications

### Service Definition

- **Protocol**: gRPC over Twirp
- **Authentication**: Requires `VideoGrants(ingress_admin=True)`
- **Base URL**: Uses same URL as other LiveKit services
- **Proto File**: `proto/livekit_ingress.proto` (needs to be added)

### API Methods

1. `create_ingress/1` - Create new ingress configuration
2. `update_ingress/1` - Update existing ingress configuration  
3. `list_ingress/0` - List all ingress configurations
4. `delete_ingress/1` - Delete ingress configuration

## Implementation Steps

### Step 1: Protocol Buffer Setup

**Timeline: 1 day**

#### 1.1 Add Protobuf Definitions

**Tasks:**

- [ ] Download latest `livekit_ingress.proto` from LiveKit repository
- [ ] Place in `proto/` directory
- [ ] Update `mix compile.proto` task to include new proto file
- [ ] Run `mix compile.proto` to generate Elixir modules

**Testing Requirements:**

- [ ] Test protobuf modules are generated correctly
- [ ] Test all required message types exist (CreateIngressRequest, IngressInfo, etc.)
- [ ] Test struct field validation for required fields (input_type, url, name)
- [ ] Test protobuf encoding/decoding functionality

### Step 2: Service Client Implementation

**Timeline: 3 days**

#### 2.1 Create IngressServiceClient Module

**Tasks:**

- [ ] Create basic client structure following existing patterns
- [ ] Implement authentication using existing AccessToken system
- [ ] Set up gRPC connection handling
- [ ] Add proper error handling for gRPC responses

**Testing Requirements:**

- [ ] Test client creation with proper configuration
- [ ] Test URL conversion (websocket to HTTP)
- [ ] Test authentication token generation with ingress_admin grants
- [ ] Test client initialization error scenarios

#### 2.2 Implement Core Methods

**Tasks:**

- [ ] Implement `create_ingress/2` method
- [ ] Implement `update_ingress/2` method  
- [ ] Implement `list_ingress/1` method
- [ ] Implement `delete_ingress/2` method
- [ ] Add proper request/response handling
- [ ] Implement timeout and retry logic

**Testing Requirements:**

- [ ] Test RTMP ingress creation with valid parameters
- [ ] Test WebRTC ingress configuration
- [ ] Test file-based input handling
- [ ] Test gRPC error handling (invalid arguments, not found, etc.)
- [ ] Test ingress listing functionality
- [ ] Test ingress update operations
- [ ] Test ingress deletion and cleanup
- [ ] Test concurrent ingress operations
- [ ] Test network failure scenarios and retries

### Step 3: CLI Integration

**Timeline: 2 days**

#### 3.1 Add CLI Commands

**Tasks:**

- [ ] Add ingress commands to `Mix.Tasks.Livekit`
- [ ] Implement `create-ingress` command
- [ ] Implement `list-ingress` command  
- [ ] Implement `update-ingress` command
- [ ] Implement `delete-ingress` command
- [ ] Add proper option parsing and validation

**Testing Requirements:**

- [ ] Test create-ingress command with RTMP parameters
- [ ] Test create-ingress command with WebRTC parameters
- [ ] Test required parameter validation
- [ ] Test list-ingress command output formatting
- [ ] Test update-ingress command functionality
- [ ] Test delete-ingress command with confirmation
- [ ] Test CLI error handling and user-friendly messages
- [ ] Test help documentation completeness

### Step 4: Documentation and Examples

**Timeline: 2 days**

#### 4.1 Update Documentation

**Tasks:**

- [ ] Add ingress section to README.md
- [ ] Update CLAUDE.md with ingress capabilities
- [ ] Add usage examples for common use cases
- [ ] Update CLI help documentation

**Testing Requirements:**

- [ ] Test README includes ingress service documentation
- [ ] Test CLAUDE.md mentions IngressServiceClient
- [ ] Test all ingress examples are valid and functional
- [ ] Test CLI help text includes all ingress commands
- [ ] Test documentation links and references work correctly

#### 4.2 Create Usage Examples

**Tasks:**

- [ ] Create RTMP stream ingress setup example
- [ ] Create WebRTC ingress configuration example
- [ ] Create file-based input handling example
- [ ] Create error handling patterns example

**Testing Requirements:**

- [ ] Test all usage examples execute without errors
- [ ] Test examples demonstrate common use cases
- [ ] Test error handling examples show proper patterns
- [ ] Test examples include necessary configuration

#### 4.3 Create Livebook Examples

**Tasks:**

- [ ] Create `examples/livebooks/ingress_basic_setup.livemd` - Basic ingress service usage
- [ ] Create `examples/livebooks/ingress_rtmp_streaming.livemd` - RTMP stream ingress tutorial
- [ ] Create `examples/livebooks/ingress_webrtc_input.livemd` - WebRTC ingress configuration
- [ ] Create `examples/livebooks/ingress_file_processing.livemd` - File-based input handling
- [ ] Create `examples/livebooks/ingress_management.livemd` - Complete lifecycle management
- [ ] Create `examples/livebooks/ingress_troubleshooting.livemd` - Common issues and debugging

**Testing Requirements:**

- [ ] Test all Livebook examples execute without errors
- [ ] Test Livebooks include interactive demonstrations
- [ ] Test examples show real ingress stream setup
- [ ] Test Livebooks include troubleshooting sections
- [ ] Test examples work with different input sources
- [ ] Test Livebooks include performance monitoring examples
- [ ] Test interactive elements (forms, inputs) work correctly
- [ ] Test examples include proper cleanup procedures

### Step 5: Performance and Load Testing

**Timeline: 2 days**

#### 5.1 Performance Tests

**Tasks:**

- [ ] Create load testing scenarios
- [ ] Test concurrent ingress creation/deletion
- [ ] Measure API response times
- [ ] Test streaming performance under load

**Testing Requirements:**

- [ ] Test concurrent ingress operations (minimum 100 parallel operations)
- [ ] Test API response time remains under 1000ms average
- [ ] Test maximum response time stays under 5000ms
- [ ] Test system stability under sustained load
- [ ] Test memory usage remains stable during load
- [ ] Test proper cleanup after load testing
- [ ] Test error rates remain acceptable under load

## Integration Requirements

### Dependencies

- [ ] Add required protobuf definitions
- [ ] Update mix.exs dependencies if needed
- [ ] Ensure gRPC client compatibility

### Configuration  

- [ ] Add ingress-specific configuration options
- [ ] Update Livekit.Config to handle ingress settings
- [ ] Add environment variable support

### Error Handling

- [ ] Implement consistent error handling patterns
- [ ] Add proper logging throughout
- [ ] Handle network failures gracefully

## Success Criteria

### Functionality

- [ ] All ingress API methods implemented and tested
- [ ] CLI commands working for all operations
- [ ] Proper error handling and validation
- [ ] Performance meets requirements (< 1s API response)

### Code Quality

- [ ] 95%+ test coverage for ingress service client
- [ ] Full Dialyzer compliance
- [ ] Credo quality checks passing
- [ ] Comprehensive documentation

### Integration

- [ ] Seamless integration with existing codebase
- [ ] No breaking changes to current APIs
- [ ] CLI help and examples updated
- [ ] README and documentation current

## Deployment Checklist

- [ ] All tests passing (unit, integration, performance)
- [ ] Documentation complete and accurate
- [ ] CLI commands tested and documented
- [ ] Error scenarios covered
- [ ] Performance benchmarks established
- [ ] Code review completed
- [ ] Integration testing with LiveKit server completed
