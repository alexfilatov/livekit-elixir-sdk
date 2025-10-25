defmodule Livekit.AccessToken.InferenceGrants do
  @moduledoc """
  Defines the structure and types for Livekit access token inference grants.
  """

  defstruct perform: false

  @type t :: %__MODULE__{
          # perform inference
          perform: boolean()
        }
end
