defmodule CpdDoc.DiscoTest do
  use ExUnit.Case, async: true

  alias CpdDoc.Disco
  alias CpdDoc.Treedoc

  @moduletag :tmp_dir

  test "lo guardado se carga igual, borrados incluidos", %{tmp_dir: dir} do
    archivo = Path.join([dir, "sub", "documento.bin"])
    {doc, _} = Treedoc.insertar(Treedoc.nuevo(), 0, "h", {:a, 1})
    {doc, _} = Treedoc.insertar(doc, 1, "o", {:a, 1})
    {doc, _} = Treedoc.borrar(doc, 0)

    assert Disco.guardar(archivo, doc) == :ok
    refute File.exists?(archivo <> ".tmp")

    cargado = Disco.cargar(archivo)
    assert cargado.atomos == doc.atomos
    assert cargado.borrados == doc.borrados
    assert Treedoc.texto(Treedoc.merge(Treedoc.nuevo(), cargado)) == "o"
  end

  test "sin archivo, archivo ausente o corrupto se arranca vacío", %{tmp_dir: dir} do
    corrupto = Path.join(dir, "corrupto.bin")
    ajeno = Path.join(dir, "ajeno.bin")
    File.write!(corrupto, "esto no es un término")
    File.write!(ajeno, :erlang.term_to_binary({:otra, :cosa}))

    for archivo <- [nil, Path.join(dir, "no_existe.bin"), corrupto, ajeno] do
      assert Disco.cargar(archivo) == Treedoc.vacio()
    end

    assert Disco.guardar(nil, Treedoc.vacio()) == :ok
  end

  test "tras reiniciar, un archivo viejo no hace repetir PosID", %{tmp_dir: dir} do
    archivo = Path.join(dir, "documento.bin")
    {antes, _} = Treedoc.insertar(Treedoc.nuevo(), 0, "a", {:nodo, 1})
    :ok = Disco.guardar(archivo, antes)
    {despues, delta_perdido} = Treedoc.insertar(antes, 1, "b", {:nodo, 1})

    reiniciado = Treedoc.merge(Treedoc.nuevo(), Disco.cargar(archivo))
    {reiniciado, delta_nuevo} = Treedoc.insertar(reiniciado, 1, "c", {:nodo, 2})

    assert Map.keys(delta_nuevo.atomos) != Map.keys(delta_perdido.atomos)
    final = Treedoc.merge(reiniciado, despues)
    assert map_size(final.atomos) == 3
    assert Treedoc.texto(final) == Treedoc.texto(Treedoc.merge(despues, reiniciado))
  end
end
