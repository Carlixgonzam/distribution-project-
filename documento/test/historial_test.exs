defmodule CpdDoc.HistorialTest do
  use ExUnit.Case, async: true

  alias CpdDoc.Historial

  @moduletag :tmp_dir

  defp op(seq) do
    %{op: :ins, from: :a, vc: %{a: seq}, pos: [{1, seq, :a}], ch: "x"}
  end

  test "lo escrito se carga en el mismo orden", %{tmp_dir: dir} do
    archivo = Path.join([dir, "sub", "a.log"])
    {:ok, fd} = Historial.abrir(archivo)
    :ok = Historial.agregar(fd, [op(1), op(2)])
    :ok = Historial.agregar(fd, [op(3)])
    :ok = Historial.agregar(fd, [])

    assert Historial.cargar(archivo) == {:ok, [op(1), op(2), op(3)]}
    assert Historial.cargar(Path.join(dir, "no_existe.log")) == {:ok, []}
  end

  test "una última línea cortada se recorta al abrir", %{tmp_dir: dir} do
    archivo = Path.join(dir, "a.log")
    {:ok, fd} = Historial.abrir(archivo)
    :ok = Historial.agregar(fd, [op(1), op(2)])
    File.write!(archivo, "AAAA", [:append])

    {:ok, fd} = Historial.abrir(archivo)
    :ok = Historial.agregar(fd, [op(3)])
    assert Historial.cargar(archivo) == {:ok, [op(1), op(2), op(3)]}
  end

  test "una línea dañada en medio deja solo el prefijo, y apartar guarda el resto", %{
    tmp_dir: dir
  } do
    archivo = Path.join(dir, "a.log")
    {:ok, fd} = Historial.abrir(archivo)
    :ok = Historial.agregar(fd, [op(1)])
    File.write!(archivo, "esto-no-es-base64!\n", [:append])
    :ok = Historial.agregar(fd, [op(3)])

    assert Historial.cargar(archivo) == {:corrupto, [op(1)], 2}
    {:ok, _} = Historial.apartar(archivo, [op(1)])
    assert Historial.cargar(archivo) == {:ok, [op(1)]}
    assert [_] = Path.wildcard(archivo <> ".danado-*")
  end
end
