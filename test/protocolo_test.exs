defmodule CpdDoc.ProtocoloTest do
  use ExUnit.Case, async: false

  alias CpdDoc.Protocolo
  alias CpdDoc.Replica
  alias CpdDoc.Treedoc

  test "un estado enviado y leído llega igual" do
    {doc, _} = Treedoc.insertar(Treedoc.nuevo(), 0, "a", {:a, 1})
    {doc, _} = Treedoc.insertar(doc, 1, "b", {:a, 1})
    {doc, _} = Treedoc.borrar(doc, 0)

    {:ok, leido} = Protocolo.leer(Protocolo.mensaje(doc))
    assert leido.atomos == doc.atomos
    assert leido.borrados == doc.borrados
  end

  test "formas y versiones desconocidas se rechazan" do
    paso = {1, {1, {:a, 1}}}

    assert Protocolo.leer({:cpd, 2, :a, {:estado, [], []}}) == :error
    assert Protocolo.leer({:cpd, 1, :a, {:otro, [], []}}) == :error
    assert Protocolo.leer({:cpd, 1, :a, {:estado, [{[paso], 97}], []}}) == :error
    assert Protocolo.leer({:cpd, 1, :a, {:estado, [{[{2, {1, {:a, 1}}}], "x"}], []}}) == :error
    assert Protocolo.leer({:cpd, 1, :a, {:estado, [{[], "x"}], []}}) == :error
    assert Protocolo.leer({:cpd, 1, :a, {:estado, [], [[paso] | :impropia]}}) == :error
    assert Protocolo.leer(:basura) == :error
    assert {:ok, _} = Protocolo.leer({:cpd, 1, :a, {:estado, [{[paso], "x"}], [[paso]]}})
  end

  test "la réplica :cpd_doc edita, recibe deltas e ignora mensajes raros sin caerse" do
    pid = Process.whereis(:cpd_doc)

    assert Replica.insertar(0, "h") == :ok
    assert Replica.insertar(1, "i") == :ok
    assert Replica.borrar(9) == {:error, :posicion_invalida}

    send(:cpd_doc, :basura)
    send(:cpd_doc, {:cpd, 99, :otro, :lo_que_sea})
    send(:cpd_doc, {:cpd, 1, :otro, {:estado, [{[{1, {1, {:a, 1}}} | :mal], "z"}], []}})
    GenServer.cast(:cpd_doc, {:cpd, 1, :otro@pc, {:estado, [{[{1, {1, {:otro, 7}}}], "!"}], []}})

    texto = Replica.texto()
    assert Process.whereis(:cpd_doc) == pid
    assert Enum.sort(String.graphemes(texto)) == ["!", "h", "i"]
  end
end
