defmodule Livekit.AccessToken.VideoGrants do
  @moduledoc """
  Defines the structure and types for Livekit access token grants.
  """

  @derive {Jason.Encoder, keys: :camel}

  defstruct room_create: nil,
            room_list: nil,
            room_record: nil,
            room_admin: nil,
            room_join: nil,
            room: "",
            destination_room: nil,
            can_publish: true,
            can_subscribe: true,
            can_publish_data: true,
            can_publish_sources: nil,
            can_update_metadata: nil,
            ingress_admin: false,
            hidden: nil,
            agent: nil

  @type t :: %__MODULE__{
          # actions on rooms
          room_create: boolean() | nil,
          room_list: boolean() | nil,
          room_record: boolean() | nil,

          # actions on a particular room
          room_admin: boolean() | nil,
          room_join: boolean() | nil,
          room: String.t() | nil,

          # allows forwarding participant to room
          destination_room: String.t() | nil,

          # permissions within a room
          can_publish: boolean(),
          can_subscribe: boolean(),
          can_publish_data: boolean(),

          # TrackSource types that a participant may publish.
          # When set, it supersedes CanPublish. Only sources explicitly set here can be
          # published
          can_publish_sources: list(String.t()) | nil,

          # by default, a participant is not allowed to update its own metadata
          can_update_metadata: boolean() | nil,

          # actions on ingress
          ingress_admin: boolean() | nil,

          # participant is not visible to other participants (useful when making bots)
          hidden: boolean() | nil,

          # indicates that the holder can register as an Agent framework worker
          agent: boolean() | nil
        }

  @doc """
  Creates a new grant for joining a room.
  """
  @spec join_room(String.t()) :: t()
  def join_room(room_name) do
    %__MODULE__{
      room: room_name,
      room_join: true
    }
  end

  @doc """
  Creates a new grant for room administration.
  """
  @spec room_admin() :: t()
  def room_admin do
    %__MODULE__{
      room_admin: true
    }
  end

  @doc """
  Creates a new grant for room recording.
  """
  @spec room_record() :: t()
  def room_record do
    %__MODULE__{
      room_record: true
    }
  end

  @doc """
  Creates a new grant for room creation.
  """
  @spec room_create() :: t()
  def room_create do
    %__MODULE__{
      room_create: true
    }
  end

  @doc """
  Creates a new grant for ingress administration.
  """
  @spec ingress_admin() :: t()
  def ingress_admin do
    %__MODULE__{
      ingress_admin: true
    }
  end
end
