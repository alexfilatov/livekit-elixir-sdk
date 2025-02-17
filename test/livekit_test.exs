defmodule LivekitTest do
  use ExUnit.Case
  doctest Livekit

  test "greets the world" do
    assert Livekit.hello() == :world
  end
end
