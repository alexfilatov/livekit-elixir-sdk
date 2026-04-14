# LiveKit Elixir SDK - Testing Patterns

## Framework
- **ExUnit** (built-in) with `ExUnit.start()` in `test/test_helper.exs`
- **16 test files** total
- **Coverage**: ExCoveralls (`mix coveralls`, `mix coveralls.html`)

## Test Organization

Tests mirror source structure: `lib/livekit/foo.ex` -> `test/livekit/foo_test.exs`

```elixir
defmodule Livekit.ConfigTest do
  use ExUnit.Case
  alias Livekit.Config

  describe "get/1" do
    test "returns config with runtime options" do
      config = Config.get(url: "wss://test.com")
      assert config.url == "wss://test.com"
    end
  end
end
```

## Async vs Sequential
- `use ExUnit.Case, async: true` — most unit tests (parallel)
- `use ExUnit.Case, async: false` — integration tests, stateful tests

## Integration Tests
Tagged with `@moduletag :integration` in `test/livekit/agents/integration_test.exs`:

```bash
mix test                        # All tests
mix test --include integration  # Only integration
mix test --exclude integration  # Skip integration
```

## Mocking Approach

### Bypass (HTTP mocking)
Creates real local HTTP server for testing API clients:

```elixir
setup do
  bypass = Bypass.open()
  client = RoomServiceClient.new("http://localhost:#{bypass.port}", key, secret)
  {:ok, bypass: bypass, client: client}
end

test "creates room", %{bypass: bypass, client: client} do
  Bypass.expect_once(bypass, "POST", "/twirp/livekit.RoomService/CreateRoom", fn conn ->
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    conn |> Plug.Conn.resp(200, Room.encode(%Room{name: "test"}))
  end)

  assert {:ok, room} = RoomServiceClient.create_room(client, "test")
end
```

### Mock library (function mocking)

```elixir
import Mock

with_mock AccessToken,
  verify: fn token, key, secret -> {:ok, %{"sha256" => hash}} end do
  assert {:ok, event} = WebhookReceiver.receive(body, token)
end
```

## GenServer Testing

```elixir
test "starts with valid config" do
  {:ok, pid} = VoiceAgent.start_link(%VoiceAgent.Config{name: "Test"})
  assert Process.alive?(pid)
end

test "processes audio" do
  {:ok, pid} = VoiceAgent.start_link(config)
  frame = AudioFrame.new(:crypto.strong_rand_bytes(4800), sample_rate: 48_000)
  assert :ok = VoiceAgent.process_audio_frame(pid, frame)
  Process.sleep(100)  # Allow async processing
  assert VoiceAgent.get_metrics(pid).audio_frames_processed > 0
end
```

## Test Fixtures
Module-level constants for shared data:

```elixir
@api_key "api_key_123"
@api_secret "secret_456"
```

## Assertion Patterns

```elixir
assert {:ok, result} = operation()     # Pattern match success
assert {:error, _} = bad_operation()   # Pattern match failure
assert Process.alive?(pid)             # Process checks
assert is_map(metrics)                 # Type checks
refute status.room_connected           # Negative assertions
```

## CI Pipeline (`.github/workflows/ci.yml`)
- Elixir 1.15, OTP 25.0
- `mix deps.get` -> `mix format --check-formatted` -> `mix test` -> `mix credo --strict`
- Dependency cache on `mix.lock` hash
