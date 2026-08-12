defmodule Livekit.Notebooks.AgentsDemoTest do
  # Not async: the notebook defines modules and starts named processes.
  use ExUnit.Case, async: false

  @moduledoc """
  Executes `notebooks/agents_demo.livemd`.

  The notebook is the acceptance test for this branch — "can somebody else
  build on this?" — and a demo that has quietly stopped working is worse than
  no demo, because it is still published and still believed. So the cells are
  extracted and run in order, sharing bindings the way Livebook does.

  It caught two real bugs the unit tests did not: `Pipeline` needs
  `{module, config}` tuples rather than a module plus separate opts, and a
  completed turn recorded only the assistant's reply, silently dropping every
  user message from the chat context.
  """

  @notebook Path.expand("../../notebooks/agents_demo.livemd", __DIR__)

  test "every cell in the agents demo notebook runs" do
    assert File.exists?(@notebook), "notebook missing: #{@notebook}"

    code =
      @notebook
      |> File.read!()
      |> extract_elixir_cells()
      # `Mix.install/1` is for a standalone Livebook session; inside the test
      # suite the application is already compiled and loaded.
      |> Enum.reject(&String.contains?(&1, "Mix.install"))
      |> Enum.join("\n")

    assert code =~ "Pipeline.start_link", "the notebook no longer exercises the pipeline"
    assert code =~ "VoiceAgent.start_link", "the notebook no longer exercises the agent"

    # Any raise here is a demo that would fail in front of whoever we sent it to.
    {result, _bindings} = Code.eval_string(code, [], __ENV__)

    assert is_map(result), "final cell should report what is and is not wired up"
    assert Map.has_key?(result, :rust_nif_built)
  end

  defp extract_elixir_cells(markdown) do
    ~r/```elixir\n(.*?)```/s
    |> Regex.scan(markdown, capture: :all_but_first)
    |> List.flatten()
  end
end
