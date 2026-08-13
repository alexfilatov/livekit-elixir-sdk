defmodule Livekit.HTTP do
  @moduledoc """
  The Tesla adapter every HTTP client in this SDK uses.

  ## Why this exists

  The adapter used to be `Tesla.Adapter.Hackney`, hardcoded in eight places,
  with `:hackney` as a hard dependency. That forced every consumer onto
  hackney whether they used it or not, and hackney pins `idna ~> 6.1` — which
  conflicts with any application already on idna 7 (swoosh, for one). An
  application that hit that conflict could not use this SDK at all without
  downgrading a transitive dependency and, as of this writing, picking up
  hackney's open SSRF and CRLF advisories along the way.

  A library has no business dictating its consumer's HTTP stack. So the
  adapter is configurable, and the default needs no dependency at all:

      # rielty, which already runs Finch
      config :livekit, tesla_adapter: {Tesla.Adapter.Finch, name: MyApp.Finch}

      # anything else
      config :livekit, tesla_adapter: Tesla.Adapter.Mint

  The default is `Tesla.Adapter.Httpc` because httpc ships with OTP: the SDK
  works out of the box with no extra dependency and no supervised pool. It is
  not the fastest adapter and it is a poor choice under load — configure Finch
  or Mint in production.

  ## Timeouts

  Adapters spell the receive timeout differently (`:recv_timeout` for
  hackney, `:receive_timeout` for Finch, `:timeout` for httpc). Callers pass
  milliseconds and this maps it, so a call site that wants sixty seconds for
  a slow LLM says so once and keeps working if the adapter changes underneath
  it.
  """

  @default_adapter Tesla.Adapter.Httpc

  @doc """
  The configured adapter, optionally with a receive timeout in milliseconds.

      Tesla.client(middleware, Livekit.HTTP.adapter())
      Tesla.client(middleware, Livekit.HTTP.adapter(60_000))
  """
  def adapter(timeout_ms \\ nil)

  def adapter(nil), do: configured()

  def adapter(timeout_ms) when is_integer(timeout_ms) do
    case configured() do
      {mod, opts} -> {mod, Keyword.merge(opts, timeout_opts(mod, timeout_ms))}
      mod when is_atom(mod) -> {mod, timeout_opts(mod, timeout_ms)}
    end
  end

  defp configured, do: Application.get_env(:livekit, :tesla_adapter, @default_adapter)

  defp timeout_opts(Tesla.Adapter.Hackney, ms), do: [recv_timeout: ms]
  defp timeout_opts(Tesla.Adapter.Finch, ms), do: [receive_timeout: ms]
  defp timeout_opts(Tesla.Adapter.Mint, ms), do: [timeout: ms]
  defp timeout_opts(Tesla.Adapter.Gun, ms), do: [timeout: ms]
  defp timeout_opts(Tesla.Adapter.Httpc, ms), do: [timeout: ms]
  # An adapter we do not know: pass the common spelling rather than crash.
  defp timeout_opts(_other, ms), do: [timeout: ms]
end
