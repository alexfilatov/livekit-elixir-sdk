defmodule Livekit.Agents.Events do
  @moduledoc """
  Typed event structs for the LiveKit Agents framework.

  All state transitions and conversation events are represented as pattern-matchable
  structs. Processes subscribed via `Livekit.Agents.EventBus` receive these structs
  as plain messages: `{:livekit_event, event}`.
  """

  defmodule UserStateChanged do
    @moduledoc "Emitted when the user state machine transitions between states."
    @type t :: %__MODULE__{
            from: :listening | :speaking | :away,
            to: :listening | :speaking | :away,
            timestamp: DateTime.t()
          }
    defstruct [:from, :to, :timestamp]
  end

  defmodule AgentStateChanged do
    @moduledoc "Emitted when the agent state machine transitions between states."
    @type t :: %__MODULE__{
            from: :initializing | :listening | :thinking | :speaking,
            to: :initializing | :listening | :thinking | :speaking,
            timestamp: DateTime.t()
          }
    defstruct [:from, :to, :timestamp]
  end

  defmodule SpeechCreated do
    @moduledoc "Emitted when the STT provider produces a final transcript."
    @type t :: %__MODULE__{
            text: String.t(),
            confidence: float() | nil,
            timestamp: DateTime.t()
          }
    defstruct [:text, :confidence, :timestamp]
  end

  defmodule ConversationItemAdded do
    @moduledoc "Emitted when a message is added to the conversation (user or assistant turn)."
    @type t :: %__MODULE__{
            role: :user | :assistant,
            content: String.t(),
            timestamp: DateTime.t()
          }
    defstruct [:role, :content, :timestamp]
  end

  defmodule ErrorEvent do
    @moduledoc "Emitted when a processing error occurs in any pipeline stage."
    @type t :: %__MODULE__{
            stage: :stt | :llm | :tts | :state_machine | :unknown,
            reason: term(),
            timestamp: DateTime.t()
          }
    defstruct [:stage, :reason, :timestamp]
  end

  defmodule TelemetryMeasurement do
    @moduledoc """
    Emitted by EventBus when it bridges a :telemetry event into the pub/sub stream.
    Consumers can pattern-match on `metric` to filter by measurement type.
    """
    @type t :: %__MODULE__{
            metric: :ttft_ms | :end_to_end_latency_ms | :token_count | atom(),
            value: number(),
            metadata: map(),
            timestamp: DateTime.t()
          }
    defstruct [:metric, :value, :metadata, :timestamp]
  end

  defmodule AgentHandoff do
    @moduledoc """
    Emitted when one agent hands off conversation context to another agent.

    ## Fields

    - `:from_agent` — identifier or PID of the agent initiating the handoff.
    - `:to_agent` — identifier or PID of the agent receiving the handoff.
    - `:mode` — `:warm` (seamless) or `:cold` (brief pause between agents).
    - `:context_size` — number of conversation items transferred.
    - `:timestamp` — UTC datetime of the handoff event.
    """
    @type t :: %__MODULE__{
            from_agent: term(),
            to_agent: term(),
            mode: :warm | :cold,
            context_size: non_neg_integer(),
            timestamp: DateTime.t()
          }
    defstruct [:from_agent, :to_agent, :mode, :context_size, :timestamp]
  end
end
