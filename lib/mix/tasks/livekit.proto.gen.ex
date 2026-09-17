defmodule Mix.Tasks.Livekit.Proto.Gen do
  @shortdoc "Regenerates lib/livekit/proto from the vendored .proto files"

  @moduledoc """
  Regenerates the protobuf modules under `lib/livekit/proto`.

  ## Why this task exists

  The `.proto` files under `proto/` used to be abridged transcriptions of
  LiveKit's, written by hand. Hand-copying a schema loses the only thing on
  the wire that matters — the field numbers — and nothing here checked. The
  fork had `EgressInfo.status` at 4 where LiveKit has it at 3, `room_name` at
  3 where LiveKit has 13, and every storage upload type's `bucket` off by
  four. A `StartRoomCompositeEgress` call therefore succeeded on the server
  and then raised `Protobuf.DecodeError` reading the reply, because field 4 on
  the wire is `room_composite`, a message, where the struct expected an enum.

  So `proto/` now holds LiveKit's own files, copied verbatim at the tag in
  `proto/UPSTREAM_VERSION`, and this task regenerates from them. Editing
  anything in `lib/livekit/proto` by hand puts the drift back.

  This replaces a `:proto` compiler that ran protoc on every build. Generated
  code is committed, so regenerating it is a deliberate act rather than a
  build step — and a build step meant anyone compiling the package needed
  protoc on their machine.

  ## Usage

      mix livekit.proto.gen

  Requires `protoc` and `protoc-gen-elixir` on PATH:

      brew install protobuf
      mix escript.install hex protobuf

  ## Updating to a newer LiveKit protocol

      git clone https://github.com/livekit/protocol /tmp/lkproto
      cd /tmp/lkproto && git checkout <tag>
      cp /tmp/lkproto/protobufs/livekit_*.proto proto/      # only the ones below
      cp /tmp/lkproto/protobufs/logger/options.proto proto/logger/
      echo <tag> > proto/UPSTREAM_VERSION
      mix livekit.proto.gen && mix test

  ## Note on `logger/options.proto`

  It is on the include path but is never generated. Its package is `logger`,
  so generating it would define `Logger.Sensitivity` and friends — colliding
  with Elixir's own `Logger`. protoc only generates for the files named as
  arguments, and it resolves the custom field options from the include path
  regardless, so leaving it out is both necessary and sufficient.
  """

  use Mix.Task

  # The transitive import closure of the services this SDK exposes. Every file
  # here is generated; anything they import must be present in proto/ for
  # protoc to resolve, whether or not it is generated.
  @protos ~w(
    livekit_models
    livekit_metrics
    livekit_room
    livekit_egress
    livekit_ingress
    livekit_webhook
    livekit_agent
    livekit_agent_dispatch
  )

  @out "lib/livekit/proto"

  @impl Mix.Task
  def run(_args) do
    ensure_executable!("protoc")
    ensure_executable!("protoc-gen-elixir")

    File.mkdir_p!(@out)

    args =
      [
        "--elixir_out=#{@out}",
        "-I",
        "proto"
      ] ++ Enum.map(@protos, &"proto/#{&1}.proto")

    Mix.shell().info("protoc #{Enum.join(args, " ")}")

    case System.cmd("protoc", args, stderr_to_stdout: true) do
      {out, 0} ->
        if out != "", do: Mix.shell().info(out)
        flatten_nested_output!()
        format_output!()
        Mix.shell().info("Regenerated #{@out} from proto/ (#{upstream_version()})")

      {out, code} ->
        Mix.raise("protoc failed (#{code}):\n#{out}")
    end
  end

  # protoc-gen-elixir emits a module for `logger/options.proto` even though it
  # is only on the include path, because the livekit protos use its field
  # options. Its package is `logger`, so those modules land as
  # `Logger.Sensitivity` and `Logger.PbExtension` — inside Elixir's own Logger
  # namespace. Nothing generated here references them (field options are
  # resolved by protoc at generation time, not at runtime), so the whole
  # subdirectory goes.
  defp flatten_nested_output! do
    Path.wildcard("#{@out}/*")
    |> Enum.filter(&File.dir?/1)
    |> Enum.each(&File.rm_rf!/1)
  end

  # protoc-gen-elixir emits `field :x, 1, ...`; this project's formatter wants
  # `field(:x, 1, ...)`. Without this the tree is left unformatted after every
  # regeneration and `mix format --check-formatted` fails in CI.
  defp format_output! do
    Mix.Task.run("format", ["#{@out}/*.pb.ex"])
  end

  defp upstream_version do
    case File.read("proto/UPSTREAM_VERSION") do
      {:ok, v} -> String.trim(v)
      _ -> "unknown version"
    end
  end

  defp ensure_executable!(bin) do
    unless System.find_executable(bin) do
      Mix.raise("""
      #{bin} not found on PATH.

        brew install protobuf
        mix escript.install hex protobuf
      """)
    end
  end
end
