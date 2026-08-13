defmodule Livekit.Grants do
  @moduledoc """
  Defines the structure and types for Livekit access token grants.
  """

  @derive {Jason.Encoder, keys: :camel}
  defstruct room: nil,
            room_join: false,
            room_list: false,
            room_record: false,
            room_admin: false,
            room_create: false,
            ingress_admin: false,
            # Required by LiveKit's agent worker endpoint. Without it the
            # WebSocket upgrade to /agent is refused with a 401, and since a
            # refused upgrade arrives as `{:gun_response, ...}` rather than
            # `{:gun_upgrade, ...}`, a worker can sit there looking healthy
            # and never be dispatched anything.
            agent: false

  @type t :: %__MODULE__{
          room: String.t() | nil,
          room_join: boolean(),
          room_list: boolean(),
          room_record: boolean(),
          room_admin: boolean(),
          room_create: boolean(),
          ingress_admin: boolean(),
          agent: boolean()
        }

  @doc """
  Creates a new grant for joining a room.
  """
  def join_room(room_name, _can_publish \\ true, _can_subscribe \\ true) do
    %__MODULE__{
      room: room_name,
      room_join: true
    }
  end

  @doc """
  Creates a new grant for room administration.
  """
  def room_admin do
    %__MODULE__{
      room_admin: true
    }
  end

  @doc """
  Creates a new grant for room recording.
  """
  def room_record do
    %__MODULE__{
      room_record: true
    }
  end

  @doc """
  Creates a new grant for room creation.
  """
  def room_create do
    %__MODULE__{
      room_create: true
    }
  end

  @doc """
  Creates a new grant for ingress administration.
  """
  def ingress_admin do
    %__MODULE__{
      ingress_admin: true
    }
  end
end
