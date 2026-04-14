defmodule Livekit.Agents.Telephony.IVRTest do
  use ExUnit.Case, async: true

  alias Livekit.Agents.Telephony.IVR.IVRRunner

  # ---------------------------------------------------------------------------
  # Test IVR workflow modules
  # ---------------------------------------------------------------------------

  defmodule SimpleGreetingIVR do
    @behaviour Livekit.Agents.Telephony.IVR

    @impl true
    def handle_step(:greeting, _ctx) do
      {:speak, "Welcome! Press 1 for sales.", next: :menu}
    end

    def handle_step(:menu, %{last_digits: "1"}) do
      {:transfer, "+15551111111"}
    end

    def handle_step(:menu, %{last_digits: "2"}) do
      {:hangup, :user_requested}
    end

    def handle_step(:menu, _ctx) do
      {:collect_digits, prompt: "Press 1 for sales or 2 to hang up.", next: :menu}
    end

    def handle_step(:done_step, _ctx), do: :done

    @impl true
    def on_complete(_reason, _ctx), do: :ok

    @impl true
    def on_timeout(step, _ctx) do
      {:speak, "Sorry, I didn't catch that.", next: step}
    end
  end

  defmodule SpeakAndDoneIVR do
    @behaviour Livekit.Agents.Telephony.IVR

    @impl true
    def handle_step(:intro, _ctx), do: {:speak, "Goodbye!"}

    @impl true
    def on_complete(_reason, _ctx), do: :ok

    @impl true
    def on_timeout(_step, _ctx), do: {:hangup, :timeout}
  end

  defmodule CollectSpeechIVR do
    @behaviour Livekit.Agents.Telephony.IVR

    @impl true
    def handle_step(:ask_name, _ctx) do
      {:collect_speech, prompt: "What is your name?", next: :confirm}
    end

    def handle_step(:confirm, %{name: name}) do
      {:speak, "Thank you, #{name}.", next: :done_step}
    end

    def handle_step(:done_step, _ctx), do: :done

    @impl true
    def on_complete(_reason, _ctx), do: :ok

    @impl true
    def on_timeout(_step, _ctx), do: {:hangup, :timeout}
  end

  # ---------------------------------------------------------------------------
  # IVRRunner tests
  # ---------------------------------------------------------------------------

  describe "IVRRunner — start_link and basic execution" do
    test "starts and immediately executes first step" do
      {:ok, runner} =
        IVRRunner.start_link(
          module: SimpleGreetingIVR,
          initial_step: :greeting,
          subscriber: self()
        )

      # Should receive the speak action from :greeting step
      assert_receive {:ivr_action, {:speak, "Welcome! Press 1 for sales."}}, 500
      IVRRunner.stop(runner)
    end

    test "sends ivr_complete when workflow finishes with :speak (no next)" do
      {:ok, runner} =
        IVRRunner.start_link(
          module: SpeakAndDoneIVR,
          initial_step: :intro,
          subscriber: self()
        )

      assert_receive {:ivr_action, {:speak, "Goodbye!"}}, 500
      assert_receive {:ivr_complete, :completed}, 500
      IVRRunner.stop(runner)
    end

    test "send ivr_complete when :done action returned" do
      {:ok, runner} =
        IVRRunner.start_link(
          module: SimpleGreetingIVR,
          initial_step: :done_step,
          subscriber: self()
        )

      assert_receive {:ivr_complete, :completed}, 500
      IVRRunner.stop(runner)
    end
  end

  describe "IVRRunner — advance/2" do
    test "advance merges context and executes next action" do
      {:ok, runner} =
        IVRRunner.start_link(
          module: SimpleGreetingIVR,
          initial_step: :menu,
          context: %{},
          subscriber: self()
        )

      # First execution of :menu with empty context -> collect_digits
      assert_receive {:ivr_action, {:collect_digits, _opts}}, 500

      # Simulate user pressing 1
      IVRRunner.advance(runner, %{last_digits: "1"})

      # Should transfer
      assert_receive {:ivr_action, {:transfer, "+15551111111"}}, 500
      assert_receive {:ivr_complete, :transferred}, 500
      IVRRunner.stop(runner)
    end

    test "advance triggering hangup sends ivr_complete with :hung_up" do
      {:ok, runner} =
        IVRRunner.start_link(
          module: SimpleGreetingIVR,
          initial_step: :menu,
          context: %{},
          subscriber: self()
        )

      assert_receive {:ivr_action, {:collect_digits, _}}, 500

      IVRRunner.advance(runner, %{last_digits: "2"})

      assert_receive {:ivr_action, {:hangup, :user_requested}}, 500
      assert_receive {:ivr_complete, :hung_up}, 500
      IVRRunner.stop(runner)
    end

    test "advance ignored after workflow completes" do
      {:ok, runner} =
        IVRRunner.start_link(
          module: SpeakAndDoneIVR,
          initial_step: :intro,
          subscriber: self()
        )

      # Drain all startup messages (speak action + complete)
      assert_receive {:ivr_action, {:speak, "Goodbye!"}}, 500
      assert_receive {:ivr_complete, :completed}, 500

      # Advancing a completed workflow should produce no new messages
      IVRRunner.advance(runner, %{extra: "data"})
      refute_receive {:ivr_action, _}, 100
      IVRRunner.stop(runner)
    end
  end

  describe "IVRRunner — timeout/1" do
    test "timeout triggers on_timeout callback" do
      {:ok, runner} =
        IVRRunner.start_link(
          module: SimpleGreetingIVR,
          initial_step: :menu,
          context: %{},
          subscriber: self()
        )

      assert_receive {:ivr_action, {:collect_digits, _}}, 500

      IVRRunner.timeout(runner)

      # on_timeout returns {:speak, "Sorry...", next: :menu}
      assert_receive {:ivr_action, {:speak, "Sorry, I didn't catch that."}}, 500
      IVRRunner.stop(runner)
    end
  end

  describe "IVRRunner — collect_speech step" do
    test "collect_speech action is sent to subscriber" do
      {:ok, runner} =
        IVRRunner.start_link(
          module: CollectSpeechIVR,
          initial_step: :ask_name,
          subscriber: self()
        )

      assert_receive {:ivr_action, {:collect_speech, opts}}, 500
      assert opts[:prompt] == "What is your name?"
      IVRRunner.stop(runner)
    end
  end

  describe "IVRRunner — get_state/1" do
    test "returns current step and context" do
      {:ok, runner} =
        IVRRunner.start_link(
          module: SimpleGreetingIVR,
          initial_step: :menu,
          context: %{call_id: "test-123"},
          subscriber: self()
        )

      # Wait for first step execution
      assert_receive {:ivr_action, _}, 500

      state = IVRRunner.get_state(runner)
      assert state.current_step == :menu
      assert state.context.call_id == "test-123"
      assert state.status == :running
      IVRRunner.stop(runner)
    end

    test "status is complete after workflow finishes" do
      {:ok, runner} =
        IVRRunner.start_link(
          module: SpeakAndDoneIVR,
          initial_step: :intro,
          subscriber: self()
        )

      assert_receive {:ivr_complete, _}, 500

      state = IVRRunner.get_state(runner)
      assert state.status == :complete
      IVRRunner.stop(runner)
    end
  end

  describe "IVRRunner — no subscriber" do
    test "works without subscriber (no messages sent, no crash)" do
      {:ok, runner} =
        IVRRunner.start_link(
          module: SpeakAndDoneIVR,
          initial_step: :intro
        )

      # Allow async execution
      Process.sleep(50)
      state = IVRRunner.get_state(runner)
      assert state.status == :complete
      IVRRunner.stop(runner)
    end
  end
end
