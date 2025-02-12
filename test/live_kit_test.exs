defmodule LiveKitTest do
  use ExUnit.Case
  doctest LiveKit

  test "greets the world" do
    assert LiveKit.hello() == :world
  end
end
