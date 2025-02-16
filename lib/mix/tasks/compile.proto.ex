defmodule Mix.Tasks.Compile.Proto do
  use Mix.Task.Compiler

  @impl Mix.Task.Compiler
  def run(_args) do
    if !System.find_executable("protoc") do
      Mix.raise("protoc not found in PATH. Please install protobuf compiler.")
    end

    File.mkdir_p!("lib/livekit/proto")

    {_, 0} = System.cmd("protoc",
      [
        "--proto_path=proto",
        "--elixir_out=lib/livekit/proto",
        "proto/livekit_room.proto"
      ],
      stderr_to_stdout: true
    )

    :ok
  end
end
