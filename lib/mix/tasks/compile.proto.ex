defmodule Mix.Tasks.Compile.Proto do
  @shortdoc "Compiles protobuf definitions"
  @moduledoc """
  Mix task for compiling protobuf definitions.
  This task is automatically run when the project is compiled.
  """

  use Mix.Task.Compiler

  @output_dir "lib/livekit/proto"

  @doc """
  Compiles protobuf files.
  Returns `{:ok, []}` if successful, or `{:error, message}` if there was an error.
  """
  @impl Mix.Task.Compiler
  @spec run(any()) :: {:ok, []} | {:error, String.t()}
  def run(_args) do
    if protoc_installed?() do
      compile_protos()
    else
      {:error, "protoc is not installed. Please install it first."}
    end
  end

  @doc """
  Returns paths to the compiled protobuf files.
  """
  @impl Mix.Task.Compiler
  @spec manifests() :: [String.t()]
  def manifests do
    Path.wildcard(Path.join(@output_dir, "*.pb.ex"))
  end

  @doc """
  Cleans up any generated files.
  """
  @impl Mix.Task.Compiler
  @spec clean() :: :ok
  def clean do
    Enum.each(manifests(), &File.rm/1)
    :ok
  end

  @doc false
  @spec protoc_installed?() :: boolean()
  defp protoc_installed? do
    case System.cmd("which", ["protoc"], stderr_to_stdout: true) do
      {_, 0} -> true
      {_, _} -> false
    end
  end

  @doc false
  @spec compile_protos() :: {:ok, []} | {:error, String.t()}
  defp compile_protos do
    proto_files = Path.wildcard("proto/**/*.proto")

    # Create output directory if it doesn't exist
    File.mkdir_p!(@output_dir)

    results =
      for proto_file <- proto_files do
        target_file = proto_to_ex_path(proto_file)

        if should_compile?(proto_file, target_file) do
          case System.cmd(
                 "protoc",
                 [
                   "--elixir_out=plugins=grpc:#{@output_dir}",
                   "--proto_path=proto",
                   proto_file
                 ],
                 stderr_to_stdout: true
               ) do
            {_, 0} -> {:ok, proto_file}
            {error, _} -> {:error, "Failed to compile #{proto_file}: #{error}"}
          end
        else
          {:ok, proto_file}
        end
      end

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, []}
      {:error, msg} -> {:error, msg}
    end
  end

  @doc false
  defp proto_to_ex_path(proto_file) do
    base = Path.basename(proto_file, ".proto")
    Path.join(@output_dir, base <> ".pb.ex")
  end

  @doc false
  defp should_compile?(proto_file, target_file) do
    not File.exists?(target_file) or
      File.stat!(proto_file).mtime > File.stat!(target_file).mtime
  end
end
