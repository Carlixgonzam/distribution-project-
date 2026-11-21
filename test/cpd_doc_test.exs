defmodule CpdDocTest do
  use ExUnit.Case
  doctest CpdDoc

  test "greets the world" do
    assert CpdDoc.hello() == :world
  end
end
