ExUnit.start(exclude: [:integration])

# Set up test configuration
Application.put_env(:livekit, :url, "wss://test.livekit.com")
Application.put_env(:livekit, :api_key, "test_key")
Application.put_env(:livekit, :api_secret, "test_secret")

# Start the agent event bus ONCE, owned by the test-runner process rather than
# by whichever test happened to touch it first.
#
# Both agent_state_machine_test and user_state_machine_test are `async: true`
# and each called `EventBus.start_link()` from inside a test. That links a
# globally-named process to a transient test process: the first test to finish
# killed the event bus, and any test running concurrently died with
# `** (EXIT from #PID<...>) shutdown`. It failed roughly one run in three,
# which is worse than failing every time.
# `EventBus.start_link/0` starts a Registry named
# `Livekit.Agents.EventBus.Registry` — that, not the EventBus module, is the
# process to look for.
case Livekit.Agents.EventBus.start_link() do
  {:ok, pid} -> Process.unlink(pid)
  {:error, {:already_started, _pid}} -> :ok
end
