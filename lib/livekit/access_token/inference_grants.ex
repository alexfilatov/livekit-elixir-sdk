defmodule Livekit.AccessToken.InferenceGrants do
  @moduledoc """
  Defines the structure and types for Livekit access token inference grants.
  """

  @derive {Jason.Encoder, keys: :camel}
  # perform inference
  defstruct perform: false

  @type t :: %__MODULE__{
          perform: boolean()
        }
end
