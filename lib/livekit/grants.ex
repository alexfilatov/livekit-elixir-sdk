defmodule LiveKit.Grants do
  @moduledoc """
  Defines the structure and types for LiveKit access token grants.
  """

  @derive {Jason.Encoder, keys: :camel}
  defstruct room: nil,
            room_join: false,
            room_list: false,
            room_record: false,
            room_admin: false,
            room_create: false,
            ingress_admin: false

  @type t :: %__MODULE__{
          room: String.t() | nil,
          room_join: boolean(),
          room_list: boolean(),
          room_record: boolean(),
          room_admin: boolean(),
          room_create: boolean(),
          ingress_admin: boolean()
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
