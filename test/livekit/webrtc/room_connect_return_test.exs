defmodule Livekit.WebRTC.RoomConnectReturnTest do
  use ExUnit.Case, async: true

  @moduledoc """
  What `room_connect` hands back on success.

  The NIF is `Result<ResourceArc<RoomResource>, Error>`, and rustler encodes
  `Ok` as the bare resource term — no `:ok` tuple. Matching only the tuple
  meant the first connection that actually succeeded died on a
  CaseClauseError naming a reference, which is a confusing way to learn that
  everything finally worked.
  """

  alias Livekit.WebRTC.Room

  defmodule BareRefNIF do
    # Exactly what the real NIF returns.
    def room_connect(_url, _token, _pid), do: make_ref()
    def room_disconnect(_ref), do: :ok
  end

  defmodule TupleNIF do
    def room_connect(_url, _token, _pid), do: {:ok, make_ref()}
    def room_disconnect(_ref), do: :ok
  end

  defmodule FailingNIF do
    def room_connect(_url, _token, _pid), do: {:error, :nope}
  end

  test "a bare resource reference is a successful connection" do
    assert {:ok, pid} =
             Room.connect(%Room.Config{url: "wss://x", token: "t", nif_module: BareRefNIF})

    assert is_reference(:sys.get_state(pid).room_ref)
    GenServer.stop(pid)
  end

  test "an {:ok, ref} tuple still works, for mocks" do
    assert {:ok, pid} =
             Room.connect(%Room.Config{url: "wss://x", token: "t", nif_module: TupleNIF})

    GenServer.stop(pid)
  end

  test "an error is still an error" do
    Process.flag(:trap_exit, true)

    assert {:error, :nope} =
             Room.connect(%Room.Config{url: "wss://x", token: "t", nif_module: FailingNIF})
  end
end
