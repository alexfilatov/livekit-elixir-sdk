defmodule Livekit.AccessToken.SipGrants do
  @moduledoc """
  Defines the structure and types for Livekit access token SIP grants.
  """

  @derive {Jason.Encoder, keys: :camel}
  # manage sip resources
  defstruct admin: false,
            # make outbound calls
            call: false

  @type t :: %__MODULE__{
          admin: boolean(),
          call: boolean()
        }

  @doc """
  Creates a new grant for SIP administration.
  """
  def admin do
    %__MODULE__{
      admin: true
    }
  end

  @doc """
  Creates a new grant for SIP call.
  """
  def call do
    %__MODULE__{
      call: true
    }
  end
end
