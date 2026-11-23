defmodule Adhoc.InstanciaTest do
  use ExUnit.Case, async: true

  alias Adhoc.Instancia

  test "el nombre de instancia se lee de vuelta" do
    texto = Instancia.nombre("doc", :"doc@172.20.10.3", servicio())

    assert texto == "doc.doc@172.20.10.3._cpd._tcp.local"
    assert Instancia.leer(texto, servicio()) == {:ok, "doc", "doc@172.20.10.3"}
  end

  test "nombres que no son instancias se rechazan" do
    assert Instancia.leer("_cpd._tcp.local", servicio()) == :error
    assert Instancia.leer("doc.sin-arroba._cpd._tcp.local", servicio()) == :error
    assert Instancia.leer("doc@172.20.10.3._cpd._tcp.local", servicio()) == :error
    assert Instancia.leer(".doc@x._cpd._tcp.local", servicio()) == :error
    assert Instancia.leer("doc.a@b@c._cpd._tcp.local", servicio()) == :error
    assert Instancia.leer("doc.doc@1.2.3.4._ssh._tcp.local", servicio()) == :error
  end

  test "solo se conecta a nodos del mismo dominio que no son uno mismo ni ya conectados" do
    servicios = [
      "_cpd._tcp.local",
      "doc.doc@172.20.10.2._cpd._tcp.local",
      "doc.doc@172.20.10.3._cpd._tcp.local",
      "doc.doc@172.20.10.4._cpd._tcp.local",
      "doc.doc@172.20.10.4._cpd._tcp.local",
      "chat.chat@172.20.10.5._cpd._tcp.local",
      "nerves-1234._ssh._tcp.local"
    ]

    nodos =
      Instancia.a_conectar(servicios, "doc", servicio(), :"doc@172.20.10.3", [:"doc@172.20.10.2"])

    assert nodos == [:"doc@172.20.10.4"]
  end

  test "otro dominio no ve a los nodos de doc" do
    servicios = ["doc.doc@172.20.10.2._cpd._tcp.local"]

    assert Instancia.a_conectar(servicios, "chat", servicio(), :"chat@172.20.10.5", []) == []
  end

  test "vecinos del hotspot de iPhone para el plan B" do
    vecinos = Instancia.vecinos("172.20.10.3", 28)

    assert length(vecinos) == 13
    refute "172.20.10.3" in vecinos
    assert Instancia.vecinos("10.0.0.1", 16) == []
  end

  defp servicio() do
    "_cpd._tcp.local"
  end
end
