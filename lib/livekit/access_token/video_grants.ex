defmodule Livekit.AccessToken.VideoGrants do
  @moduledoc """
  Defines the structure and types for Livekit access token grants.
  """

  @derive {Jason.Encoder, keys: :camel}
  # actions on rooms
  defstruct room_create: nil,
            room_list: nil,
            room_record: nil,
            # actions on a particular room
            room_admin: nil,
            room_join: nil,
            room: "",
            # allows forwarding participant to room
            destination_room: nil,
            # permissions within a room
            can_publish: true,
            can_subscribe: true,
            can_publish_data: true,
            # TrackSource types that a participant may publish.
            # When set, it supersedes CanPublish. Only sources explicitly set here can be
            # published
            can_publish_sources: nil,
            # by default, a participant is not allowed to update its own metadata
            can_update_metadata: nil,
            # actions on ingress
            ingress_admin: false,
            # participant is not visible to other participants (useful when making bots)
            hidden: nil,
            # indicates that the holder can register as an Agent framework worker
            agent: nil

  @type t :: %__MODULE__{
          room_create: boolean() | nil,
          room_list: boolean() | nil,
          room_record: boolean() | nil,
          room_admin: boolean() | nil,
          room_join: boolean() | nil,
          room: String.t() | nil,
          destination_room: String.t() | nil,
          can_publish: boolean(),
          can_subscribe: boolean(),
          can_publish_data: boolean(),
          can_publish_sources: list(String.t()) | nil,
          can_update_metadata: boolean() | nil,
          ingress_admin: boolean() | nil,
          hidden: boolean() | nil,
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

  @doc """
  Updates the grants with the given options.
  """
  @spec update_grants(grants :: t(), opts :: Keyword.t()) :: t()
  def update_grants(%__MODULE__{} = grants, opts) do
    Enum.reduce(opts, grants, fn {key, value}, acc ->
      Map.replace(acc, key, value)
    end)
  end
end
