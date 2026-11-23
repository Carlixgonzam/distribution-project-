defmodule CpdDoc.DescubrimientoTest do
  use ExUnit.Case, async: true

  alias CpdDoc.Descubrimiento

  test "vecinos en la subred /28 del hotspot de iPhone" do
    vecinos = Descubrimiento.vecinos("172.20.10.3", 28)

    assert length(vecinos) == 13
    assert hd(vecinos) == "172.20.10.1"
    assert List.last(vecinos) == "172.20.10.14"
    refute "172.20.10.3" in vecinos
  end

  test "vecinos en una /24 y en una /28 que no empieza en 0" do
    assert length(Descubrimiento.vecinos("192.168.43.10", 24)) == 253

    assert Descubrimiento.vecinos("10.0.0.20", 28) ==
             Enum.map(17..30, fn x -> "10.0.0.#{x}" end) -- ["10.0.0.20"]
  end

  test "subredes más grandes que /24 no se recorren" do
    assert Descubrimiento.vecinos("10.1.2.3", 16) == []
  end
end
