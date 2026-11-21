defmodule CpdDoc.TreedocTest do
  use ExUnit.Case, async: true

  alias CpdDoc.Treedoc

  defp escribir(doc, i, cadena, sitio) do
    String.graphemes(cadena)
    |> Enum.with_index(i)
    |> Enum.reduce(doc, fn {caracter, j}, acc ->
      {acc, _delta} = Treedoc.insertar(acc, j, caracter, sitio)
      acc
    end)
  end

  defp escribir_al_reves(doc, i, cadena, sitio) do
    String.graphemes(cadena)
    |> Enum.reverse()
    |> Enum.reduce(doc, fn caracter, acc ->
      {acc, _delta} = Treedoc.insertar(acc, i, caracter, sitio)
      acc
    end)
  end

  defp contenido(doc) do
    {doc.atomos, doc.borrados}
  end

  defp aplicar(doc, deltas) do
    Enum.reduce(deltas, doc, fn delta, acc -> Treedoc.merge(acc, delta) end)
  end

  test "edición concurrente: MAR, una réplica borra la R y otra inserta A al inicio" do
    r1 = escribir(Treedoc.nuevo(), 0, "MAR", {:a, 1})
    r2 = Treedoc.merge(Treedoc.nuevo(), r1)

    {r1, d1} = Treedoc.borrar(r1, 2)
    {r2, d2} = Treedoc.insertar(r2, 0, "A", {:b, 1})

    r1 = Treedoc.merge(r1, d2)
    r2 = Treedoc.merge(r2, d1)

    assert Treedoc.texto(r1) == "AMA"
    assert Treedoc.texto(r2) == "AMA"
  end

  test "mismo hueco: X de {:a, 1} e Y de {:b, 1} dan XY en cualquier orden" do
    {_, dx} = Treedoc.insertar(Treedoc.nuevo(), 0, "X", {:a, 1})
    {_, dy} = Treedoc.insertar(Treedoc.nuevo(), 0, "Y", {:b, 1})

    assert Treedoc.texto(aplicar(Treedoc.nuevo(), [dx, dy])) == "XY"
    assert Treedoc.texto(aplicar(Treedoc.nuevo(), [dy, dx])) == "XY"
  end

  test "un borrado que llega antes que su inserción oculta el carácter" do
    {r1, d_insertar} = Treedoc.insertar(Treedoc.nuevo(), 0, "Z", {:a, 1})
    {_, d_borrar} = Treedoc.borrar(r1, 0)

    r2 = Treedoc.merge(Treedoc.nuevo(), d_borrar)
    assert Treedoc.texto(r2) == ""

    r2 = Treedoc.merge(r2, d_insertar)
    assert Treedoc.texto(r2) == ""
    assert map_size(r2.atomos) == 1
  end

  test "deltas duplicados no cambian nada" do
    {r1, d1} = Treedoc.insertar(Treedoc.nuevo(), 0, "h", {:a, 1})
    {r1, d2} = Treedoc.insertar(r1, 1, "o", {:a, 1})
    {_, d3} = Treedoc.borrar(r1, 0)
    deltas = [d1, d2, d3]

    una_vez = aplicar(Treedoc.nuevo(), deltas)
    dos_veces = aplicar(Treedoc.nuevo(), deltas ++ deltas)
    intercalados = aplicar(Treedoc.nuevo(), [d1, d1, d2, d3, d2, d3])

    assert dos_veces == una_vez
    assert intercalados == una_vez
    assert Treedoc.texto(una_vez) == "o"
  end

  test "reinicio: mismo node() con otra encarnación no choca y merge da el mismo texto" do
    {a, da} = Treedoc.insertar(Treedoc.nuevo(), 0, "x", {:nodo, 1})
    {b, db} = Treedoc.insertar(Treedoc.nuevo(), 0, "y", {:nodo, 2})

    assert Map.keys(da.atomos) != Map.keys(db.atomos)
    assert map_size(Treedoc.merge(a, b).atomos) == 2
    assert Treedoc.texto(Treedoc.merge(a, b)) == Treedoc.texto(Treedoc.merge(b, a))
  end

  test "leyes del merge y convergencia en 200 ejecuciones aleatorias de 3 réplicas" do
    for _ <- 1..200 do
      {[a, b, c], deltas} = simular()

      assert contenido(Treedoc.merge(a, b)) == contenido(Treedoc.merge(b, a))

      assert contenido(Treedoc.merge(Treedoc.merge(a, b), c)) ==
               contenido(Treedoc.merge(a, Treedoc.merge(b, c)))

      assert contenido(Treedoc.merge(a, a)) == contenido(a)

      finales =
        for r <- [a, b, c] do
          aplicar(r, Enum.shuffle(deltas ++ Enum.take_random(deltas, 10)))
        end

      [f1, f2, f3] = finales
      assert contenido(f1) == contenido(f2)
      assert contenido(f2) == contenido(f3)
      assert Treedoc.texto(f1) == Treedoc.texto(f2)
      assert Treedoc.texto(f2) == Treedoc.texto(f3)
      assert contenido(f1) == contenido(aplicar(Treedoc.vacio(), deltas))
    end
  end

  test "sin intercalado: Alice y Charlie a la vez antes del ! escribiendo hacia adelante" do
    base = escribir(Treedoc.nuevo(), 0, "Hello!", {:base, 1})
    alice = escribir(Treedoc.merge(Treedoc.nuevo(), base), 5, " Alice", {:alice, 1})
    charlie = escribir(Treedoc.merge(Treedoc.nuevo(), base), 5, " Charlie", {:charlie, 1})

    assert Treedoc.texto(Treedoc.merge(alice, charlie)) == "Hello Alice Charlie!"
    assert Treedoc.texto(Treedoc.merge(charlie, alice)) == "Hello Alice Charlie!"
  end

  test "sin intercalado: Alice y Charlie a la vez antes del ! escribiendo hacia atrás" do
    base = escribir(Treedoc.nuevo(), 0, "Hello!", {:base, 1})
    alice = escribir_al_reves(Treedoc.merge(Treedoc.nuevo(), base), 5, " Alice", {:alice, 1})

    charlie =
      escribir_al_reves(Treedoc.merge(Treedoc.nuevo(), base), 5, " Charlie", {:charlie, 1})

    assert Treedoc.texto(alice) == "Hello Alice!"
    assert Treedoc.texto(Treedoc.merge(alice, charlie)) == "Hello Alice Charlie!"
    assert Treedoc.texto(Treedoc.merge(charlie, alice)) == "Hello Alice Charlie!"
  end

  test "sin intercalado sin importar quién escribió la base" do
    for autor <- [{:base, 1}, {:alice, 1}, {:charlie, 1}] do
      base = escribir(Treedoc.nuevo(), 0, "Hello!", autor)
      inicio_alice = if autor == {:alice, 1}, do: base, else: Treedoc.merge(Treedoc.nuevo(), base)

      inicio_charlie =
        if autor == {:charlie, 1}, do: base, else: Treedoc.merge(Treedoc.nuevo(), base)

      alice = escribir(inicio_alice, 5, " Alice", {:alice, 1})
      charlie = escribir(inicio_charlie, 5, " Charlie", {:charlie, 1})
      t1 = Treedoc.texto(Treedoc.merge(alice, charlie))
      t2 = Treedoc.texto(Treedoc.merge(charlie, alice))

      assert t1 == t2
      assert t1 in ["Hello Alice Charlie!", "Hello Charlie Alice!"]
    end
  end

  test "inserción local: 2000 inserciones y borrados aleatorios coinciden con un String" do
    letras = String.graphemes("abcdefghijklmnopqrstuvwxyz ")

    {doc, cadena} =
      Enum.reduce(1..2000, {Treedoc.nuevo(), ""}, fn _, {doc, cadena} ->
        n = String.length(cadena)

        if n > 0 and :rand.uniform(3) == 1 do
          i = Enum.random(0..(n - 1))
          {doc, _} = Treedoc.borrar(doc, i)
          {doc, String.slice(cadena, 0, i) <> String.slice(cadena, i + 1, n)}
        else
          i = Enum.random(0..n)
          c = Enum.random(letras)
          {doc, _} = Treedoc.insertar(doc, i, c, {:a, 1})
          {doc, String.slice(cadena, 0, i) <> c <> String.slice(cadena, i, n)}
        end
      end)

    assert Treedoc.texto(doc) == cadena
  end

  test "posiciones y caracteres inválidos" do
    {doc, _} = Treedoc.insertar(Treedoc.nuevo(), 0, "a", {:a, 1})

    assert Treedoc.borrar(doc, 1) == {:error, :posicion_invalida}
    assert Treedoc.borrar(doc, -1) == {:error, :posicion_invalida}
    assert Treedoc.insertar(doc, 2, "b", {:a, 1}) == {:error, :posicion_invalida}
    assert Treedoc.insertar(doc, 0, "bc", {:a, 1}) == {:error, :caracter_invalido}
  end

  defp simular() do
    sitios = %{1 => {:a, 1}, 2 => {:b, 1}, 3 => {:c, 1}}
    replicas = %{1 => Treedoc.nuevo(), 2 => Treedoc.nuevo(), 3 => Treedoc.nuevo()}

    {replicas, deltas} =
      Enum.reduce(1..20, {replicas, []}, fn _, {replicas, deltas} ->
        k = Enum.random(1..3)
        doc = recibir_alguno(replicas[k], deltas)
        {doc, delta} = operacion_aleatoria(doc, sitios[k])
        {Map.put(replicas, k, doc), [delta | deltas]}
      end)

    {[replicas[1], replicas[2], replicas[3]], deltas}
  end

  defp recibir_alguno(doc, []) do
    doc
  end

  defp recibir_alguno(doc, deltas) do
    if :rand.uniform(2) == 1 do
      Treedoc.merge(doc, Enum.random(deltas))
    else
      doc
    end
  end

  defp operacion_aleatoria(doc, sitio) do
    n = length(Treedoc.visibles(doc))

    if n > 0 and :rand.uniform(3) == 1 do
      Treedoc.borrar(doc, Enum.random(0..(n - 1)))
    else
      Treedoc.insertar(doc, Enum.random(0..n), Enum.random(["a", "b", "c"]), sitio)
    end
  end
end
