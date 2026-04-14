defmodule Livekit.Agents.JobContext do
  @moduledoc """
  Job context for managing agent job execution and room connections.

  JobContext provides the execution environment for agent jobs, including:
  - Room connection management
  - Participant tracking
  - Job metadata and lifecycle management
  - Authentication and authorization context
  """

  require Logger

  @type t :: %__MODULE__{
    job_id: String.t(),
    room_name: String.t(),
    participant_identity: String.t(),
    server_url: String.t(),
    api_key: String.t(),
    api_secret: String.t(),
    metadata: map(),
    created_at: DateTime.t()
  }

  defstruct [
    :job_id,
    :room_name,
    :participant_identity,
    :server_url,
    :api_key,
    :api_secret,
    metadata: %{},
    created_at: nil
  ]

  @doc """
  Creates a new JobContext.

  ## Examples

      iex> context = Livekit.Agents.JobContext.new(%{
      ...>   job_id: "job-123",
      ...>   room_name: "my-room",
      ...>   participant_identity: "agent",
      ...>   server_url: "ws://localhost:7880",
      ...>   api_key: "your-key",
      ...>   api_secret: "your-secret"
      ...> })
      iex> context.job_id
      "job-123"
  """
  @spec new(map()) :: t()
  def new(attrs) do
    struct(__MODULE__, Map.put(attrs, :created_at, DateTime.utc_now()))
  end

  @doc """
  Gets job duration in seconds.
  """
  @spec job_duration(t()) :: non_neg_integer()
  def job_duration(%__MODULE__{created_at: created_at}) do
    DateTime.diff(DateTime.utc_now(), created_at, :second)
  end

  @doc """
  Creates a room access token for this job context.
  """
  @spec create_room_token(t(), keyword()) :: String.t()
  def create_room_token(context, opts \\ []) do
    ttl = Keyword.get(opts, :ttl, 3600)

    grants = %{
      room_join: true,
      room: context.room_name,
      can_publish: Keyword.get(opts, :can_publish, true),
      can_subscribe: Keyword.get(opts, :can_subscribe, true),
      can_publish_data: Keyword.get(opts, :can_publish_data, true)
    }

    Livekit.AccessToken.new(context.api_key, context.api_secret)
    |> Livekit.AccessToken.with_identity(context.participant_identity)
    |> Livekit.AccessToken.with_ttl(ttl)
    |> Livekit.AccessToken.add_grant(grants)
    |> Livekit.AccessToken.to_jwt()
  end

  @doc """
  Gets job metadata value by key.
  """
  @spec get_metadata(t(), String.t(), term()) :: term()
  def get_metadata(context, key, default \\ nil) do
    Map.get(context.metadata, key, default)
  end

  @doc """
  Updates job metadata.
  """
  @spec put_metadata(t(), String.t(), term()) :: t()
  def put_metadata(context, key, value) do
    new_metadata = Map.put(context.metadata, key, value)
    %{context | metadata: new_metadata}
  end

  @doc """
  Merges metadata into the job context.
  """
  @spec merge_metadata(t(), map()) :: t()
  def merge_metadata(context, metadata) do
    new_metadata = Map.merge(context.metadata, metadata)
    %{context | metadata: new_metadata}
  end

  @doc """
  Converts JobContext to a map representation.
  """
  @spec to_map(t()) :: map()
  def to_map(context) do
    %{
      job_id: context.job_id,
      room_name: context.room_name,
      participant_identity: context.participant_identity,
      server_url: context.server_url,
      metadata: context.metadata,
      created_at: context.created_at,
      job_duration_seconds: job_duration(context)
    }
  end

  @doc """
  Validates that the job context has all required fields.
  """
  @spec validate(t()) :: :ok | {:error, term()}
  def validate(context) do
    required_fields = [:job_id, :room_name, :participant_identity, :server_url, :api_key, :api_secret]

    missing_fields = Enum.filter(required_fields, fn field ->
      value = Map.get(context, field)
      is_nil(value) || (is_binary(value) && String.trim(value) == "")
    end)

    case missing_fields do
      [] -> :ok
      fields -> {:error, {:missing_required_fields, fields}}
    end
  end

  @doc """
  Creates a sanitized version of the context for logging (removes secrets).
  """
  @spec sanitize_for_logging(t()) :: map()
  def sanitize_for_logging(context) do
    %{
      job_id: context.job_id,
      room_name: context.room_name,
      participant_identity: context.participant_identity,
      server_url: context.server_url,
      api_key: mask_secret(context.api_key),
      api_secret: mask_secret(context.api_secret),
      metadata: context.metadata,
      created_at: context.created_at
    }
  end

  # Private Functions

  defp mask_secret(nil), do: nil
  defp mask_secret(secret) when is_binary(secret) do
    case String.length(secret) do
      len when len <= 4 -> String.duplicate("*", len)
      len -> String.slice(secret, 0, 2) <> String.duplicate("*", len - 4) <> String.slice(secret, -2, 2)
    end
  end
  defp mask_secret(_), do: "***"
end