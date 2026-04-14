defmodule Livekit.Agents.TTS.OpenAI.Cache do
  @moduledoc """
  Agent-based response cache for OpenAI TTS audio binaries.

  Provides a simple in-memory cache with configurable TTL (time-to-live) and
  maximum entry count. When the cache is full, the oldest entry is evicted to
  make room for a new one (LRU-style eviction on insertion).

  The cache is not globally supervised — callers start it themselves with
  `start_link/1` and pass the returned pid to subsequent calls.

  ## Example

      {:ok, pid} = Cache.start_link(ttl_seconds: 60, max_entries: 100)
      Cache.put(pid, "key", audio_binary)
      {:ok, audio} = Cache.get(pid, "key")
      Cache.clear(pid)
  """

  @doc """
  Starts the cache Agent.

  ## Options

    - `:ttl_seconds` — time-to-live in seconds (default: `3600`)
    - `:max_entries` — maximum number of entries before eviction (default: `500`)
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    ttl_ms = Keyword.get(opts, :ttl_seconds, 3600) * 1000
    max_entries = Keyword.get(opts, :max_entries, 500)

    Agent.start_link(fn ->
      %{
        entries: %{},
        insertion_order: [],
        ttl_ms: ttl_ms,
        max_entries: max_entries
      }
    end)
  end

  @doc """
  Looks up `key` in the cache.

  Returns `{:ok, value}` if the entry exists and has not expired, or `:miss`
  if the key is absent or the TTL has elapsed.
  """
  @spec get(pid(), String.t()) :: {:ok, binary()} | :miss
  def get(cache_pid, key) do
    Agent.get(cache_pid, fn state ->
      now = System.monotonic_time(:millisecond)

      check_entry(Map.get(state.entries, key), now, state.ttl_ms)
    end)
  end

  @doc """
  Stores `value` under `key`.

  If the cache already holds `max_entries` entries, the oldest entry is evicted
  before inserting the new one.
  """
  @spec put(pid(), String.t(), binary()) :: :ok
  def put(cache_pid, key, value) do
    Agent.update(cache_pid, fn state ->
      now = System.monotonic_time(:millisecond)

      # Remove existing entry from insertion_order if key already present
      new_order = List.delete(state.insertion_order, key)

      # Check if we need to evict the oldest entry
      {evict_key, new_order2} =
        if length(new_order) >= state.max_entries do
          [oldest | rest] = new_order
          {oldest, rest}
        else
          {nil, new_order}
        end

      new_entries =
        state.entries
        |> Map.delete(evict_key)
        |> Map.put(key, {value, now})

      %{state | entries: new_entries, insertion_order: new_order2 ++ [key]}
    end)
  end

  @doc """
  Removes all entries from the cache.
  """
  @spec clear(pid()) :: :ok
  def clear(cache_pid) do
    Agent.update(cache_pid, fn state ->
      %{state | entries: %{}, insertion_order: []}
    end)
  end

  # Private Helpers

  defp check_entry(nil, _now, _ttl_ms), do: :miss

  defp check_entry({value, inserted_at}, now, ttl_ms) do
    if now - inserted_at <= ttl_ms, do: {:ok, value}, else: :miss
  end
end
