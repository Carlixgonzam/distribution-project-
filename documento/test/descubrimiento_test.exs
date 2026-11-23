defmodule CpdDoc.DescubrimientoTest do
  use ExUnit.Case, async: true

  alias CpdDoc.Descubrimiento

  test "vecinos en una /24, una /28 y una red mayor que /24 (se barre la /24 propia)" do
    vecinos = Descubrimiento.vecinos("192.168.1.37", 24)
    assert length(vecinos) == 253
    assert hd(vecinos) == "192.168.1.1"
    assert List.last(vecinos) == "192.168.1.254"
    refute "192.168.1.37" in vecinos

    assert Descubrimiento.vecinos("10.0.0.20", 28) ==
             Enum.map(17..30, fn x -> "10.0.0.#{x}" end) -- ["10.0.0.20"]

    assert length(Descubrimiento.vecinos("10.1.2.3", 16)) == 253
  end

  test "paquetes de anuncio del contrato" do
    assert Descubrimiento.paquete(:"pi-pe@172.20.10.4") == "crdt-treedoc-1 pi-pe@172.20.10.4"

    assert Descubrimiento.leer_paquete("crdt-treedoc-1 pi-pe@172.20.10.4") ==
             {:ok, :"pi-pe@172.20.10.4"}

    assert Descubrimiento.leer_paquete("crdt-treedoc-1 nerves-1a2b-3f9c07@192.168.1.5") ==
             {:ok, :"nerves-1a2b-3f9c07@192.168.1.5"}

    for malo <- [
          "otra cosa",
          "crdt-treedoc-1 ",
          "crdt-treedoc-1 sin_arroba",
          "crdt-treedoc-1 a@b.local",
          "crdt-treedoc-1 a b@1.2.3.4"
        ] do
      assert Descubrimiento.leer_paquete(malo) == :error
    end
  end
end
