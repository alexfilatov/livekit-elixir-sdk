# LiveKit Elixir SDK - Coding Conventions

## Formatting & Linting
- **Formatter**: `mix format` with `.formatter.exs` (inputs: `{config,lib,test}/**/*.{ex,exs}`)
- **Linter**: Credo with `strict: true` (`.credo.exs`)
- **Max line length**: 120 chars (low priority)
- **CI**: `mix format --check-formatted` + `mix credo --strict`

## Module Structure Pattern

Every module follows this order:
1. `@moduledoc` with markdown documentation
2. `use GenServer` / `require Logger` / aliases
3. Nested `Config` struct with `@type t`
4. Nested `State` struct with `@moduledoc false` (for GenServers)
5. Client API functions (public, with `@doc` and `@spec`)
6. GenServer callbacks (with `@impl true`)
7. Private helper functions (under `# Private Helpers` comment)

## GenServer Conventions

```elixir
# Always use @impl true
@impl true
def init(config) do
  case validate_config(config) do
    :ok -> {:ok, %State{config: config}}
    {:error, reason} -> {:stop, reason}
  end
end

# State updates via struct update syntax
%{state | status: :connected, last_heartbeat: DateTime.utc_now()}

# Explicit timeouts on all calls
GenServer.call(pid, :get_status, 5_000)
```

## Error Handling

Standard `{:ok, result}` / `{:error, reason}` tuples everywhere:

```elixir
# with-expression for chaining
with {:ok, config} <- get_config(),
     {:ok, claims} <- validate_token(auth_header, config),
     :ok <- validate_sha(claims, body) do
  {:ok, result}
end

# Pattern matching in case
case Tesla.post(client, path, body) do
  {:ok, %{status: 200, body: body}} -> {:ok, decode(body)}
  {:ok, %{status: status, body: body}} -> {:error, {status, body}}
  {:error, reason} -> {:error, reason}
end
```

## Naming

- **Modules**: PascalCase dot-notation (`Livekit.Agents.STT.Deepgram`)
- **Functions**: snake_case with prefixes: `get_*`, `with_*`, `add_*`, `validate_*`
- **Variables**: descriptive snake_case (`audio_data`, `participant_identity`)
- **Builder pattern**: `with_*` functions returning modified struct

```elixir
AccessToken.new(key, secret)
|> AccessToken.with_identity("user123")
|> AccessToken.with_ttl(3600)
|> AccessToken.to_jwt()
```

## Provider Injection

AI providers configured as `{module, config}` tuples:

```elixir
%VoiceAgent.Config{
  stt: {Livekit.Agents.STT.Deepgram, %{api_key: "key"}},
  llm: {Livekit.Agents.LLM.OpenAI, %{api_key: "key"}},
  tts: {Livekit.Agents.TTS.OpenAI, %{api_key: "key"}}
}
```

## Documentation

- `@moduledoc` required on all public modules (Credo enforced)
- `@doc` on all public functions with examples for complex ones
- `@spec` on all public functions and GenServer callbacks

## Configuration Precedence

Runtime options > Application environment > Environment variables > Defaults

## Metrics Pattern

All major components track metrics via state maps:

```elixir
metrics: %{
  turns_processed: 0,
  audio_frames_processed: 0,
  errors: 0,
  last_activity: nil
}
```

Retrieved via `get_metrics/1` functions.
