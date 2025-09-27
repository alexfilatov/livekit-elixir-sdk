defmodule Livekit.AccessToken.SIPGrants do
  @moduledoc """
  Defines the structure and types for Livekit access token SIP grants.
  """

  @derive {Jason.Encoder, keys: :camel}
  defstruct admin: false,
            call: false

  @type t :: %__MODULE__{
          # manage sip resources
          admin: boolean(),

          # make outbound calls
          call: boolean()
        }
end
