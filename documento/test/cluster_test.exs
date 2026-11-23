defmodule CpdDoc.ClusterTest do
  use ExUnit.Case, async: false

  import CpdDoc.Nodos, only: [llamar: 3, llamar: 4, eventualmente: 1]

  @moduletag :tmp_dir
  @moduletag timeout: 180_000

  setup %{tmp_dir: dir} do
    nodos =
      for n <- [:a, :b, :c] do
        CpdDoc.Nodos.iniciar(:"#{n}#{System.unique_integer([:positive])}", dir)
      end

    on_exit(fn -> detener(nodos) end)
    [{pa, a}, {pb, b}, {pc, c}] = nodos
    %{pa: pa, pb: pb, pc: pc, a: a, b: b, c: c, todos: [pa, pb, pc], dir: dir}
  end

  defp detener(nodos) do
    for {pid, _} <- nodos do
      :peer.stop(pid)
    end
  end

  defp unir(pid, nodo) do
    true = llamar(pid, Node, :connect, [nodo])
  end

  defp separar(pid, nodo) do
    llamar(pid, Node, :disconnect, [nodo])
  end

  defp malla(c) do
    unir(c.pa, c.b)
    unir(c.pa, c.c)
    unir(c.pb, c.c)
  end

  defp textos(pids) do
    Enum.map(pids, fn p -> llamar(p, CpdDoc, :texto) end)
  end

  defp iguales?(pids) do
    length(Enum.uniq(textos(pids))) == 1
  end

  defp iguales?(pids, esperado) do
    Enum.uniq(textos(pids)) == [esperado]
  end

  test "una edición local llega a todos, los borrados también", c do
    malla(c)
    :ok = llamar(c.pa, CpdDoc, :insertar, [0, "Hola"])
    assert eventualmente(fn -> iguales?(c.todos, "Hola") end)

    :ok = llamar(c.pb, CpdDoc, :insertar, [4, " mundo"])
    :ok = llamar(c.pc, CpdDoc, :borrar, [0, 1])
    assert eventualmente(fn -> iguales?(c.todos, "ola mundo") end)

    estado = llamar(c.pa, CpdDoc, :estado)
    assert estado.reloj == %{c.a => 4, c.b => 6, c.c => 1}
    assert estado.en_espera == []
  end

  test "escrituras simultáneas en la misma posición convergen sin intercalar palabras", c do
    malla(c)
    :ok = llamar(c.pa, CpdDoc, :insertar, [0, "[]"])
    assert eventualmente(fn -> iguales?(c.todos, "[]") end)

    tareas =
      for {p, w} <- [{c.pa, "uno"}, {c.pb, "dos"}, {c.pc, "tres"}] do
        Task.async(fn -> llamar(p, CpdDoc, :insertar, [1, w]) end)
      end

    for tarea <- tareas do
      Task.await(tarea)
    end

    assert eventualmente(fn -> iguales?(c.todos) end)
    [t | _] = textos(c.todos)

    for w <- ~w(uno dos tres) do
      assert String.contains?(t, w), "#{w} intercalada en #{t}"
    end

    assert String.length(t) == 12
  end

  test "reenvío: en una cadena A-B-C, con A y C sin conexión directa, llega todo", c do
    unir(c.pa, c.b)
    unir(c.pb, c.c)
    refute c.c in llamar(c.pa, Node, :list, [])

    :ok = llamar(c.pa, CpdDoc, :insertar, [0, "desde A"])
    assert eventualmente(fn -> iguales?(c.todos, "desde A") end)
    :ok = llamar(c.pc, CpdDoc, :insertar, [0, "C: "])
    assert eventualmente(fn -> iguales?(c.todos, "C: desde A") end)
  end

  test "partición: los dos lados siguen editando y convergen al reconectar", c do
    malla(c)
    :ok = llamar(c.pa, CpdDoc, :insertar, [0, "base"])
    assert eventualmente(fn -> iguales?(c.todos, "base") end)

    separar(c.pc, c.a)
    separar(c.pc, c.b)
    :ok = llamar(c.pa, CpdDoc, :insertar, [4, " AB"])
    :ok = llamar(c.pc, CpdDoc, :insertar, [0, "C "])
    :ok = llamar(c.pc, CpdDoc, :borrar, [2, 1])
    assert eventualmente(fn -> iguales?([c.pa, c.pb], "base AB") end)
    assert llamar(c.pc, CpdDoc, :texto) == "C ase"

    unir(c.pc, c.a)
    unir(c.pc, c.b)
    assert eventualmente(fn -> iguales?(c.todos, "C ase AB") end)
  end

  test "reinicio: la réplica vuelve desde su log, se pone al día y sigue numerando", c do
    malla(c)
    :ok = llamar(c.pb, CpdDoc, :insertar, [0, "ab"])
    assert eventualmente(fn -> iguales?(c.todos, "ab") end)

    :ok = llamar(c.pb, Supervisor, :terminate_child, [CpdDoc.Supervisor, CpdDoc.Replica])
    :ok = llamar(c.pa, CpdDoc, :insertar, [2, "cd"])
    {:ok, _} = llamar(c.pb, Supervisor, :restart_child, [CpdDoc.Supervisor, CpdDoc.Replica])

    assert eventualmente(fn -> iguales?(c.todos, "abcd") end)
    :ok = llamar(c.pb, CpdDoc, :insertar, [4, "e"])
    assert eventualmente(fn -> iguales?(c.todos, "abcde") end)
    assert llamar(c.pa, CpdDoc, :estado).reloj[c.b] == 3
  end

  test "un nodo nuevo recibe todo el historial al conectarse", c do
    unir(c.pa, c.b)
    :ok = llamar(c.pa, CpdDoc, :insertar, [0, "hola"])
    :ok = llamar(c.pb, CpdDoc, :borrar, [0, 1])
    assert eventualmente(fn -> iguales?([c.pa, c.pb], "ola") end)

    unir(c.pc, c.b)
    assert eventualmente(fn -> iguales?(c.todos, "ola") end)
  end

  test "mensajes del contrato de otro grupo se aplican y la basura se ignora", c do
    unir(c.pa, c.b)
    :ok = llamar(c.pa, CpdDoc, :insertar, [0, "hola"])
    assert eventualmente(fn -> iguales?([c.pa, c.pb], "hola") end)

    otro = :"team@127.0.0.1"
    m = %{op: :ins, from: otro, vc: %{otro => 1}, pos: [{0, 1, otro}], ch: "T"}
    espera = %{op: :ins, from: otro, vc: %{otro => 3}, pos: [{1, 3, otro}], ch: "!"}
    replica = {Crdt.Replica, c.a}

    for basura <- [{:remote, %{}}, {:remote, %{m | ch: "ab"}}, :basura, {:hello, "no atom"}] do
      :ok = llamar(c.pb, GenServer, :cast, [replica, basura])
    end

    :ok = llamar(c.pb, GenServer, :cast, [replica, {:remote, espera}])
    :ok = llamar(c.pb, GenServer, :cast, [replica, {:remote, m}])
    assert eventualmente(fn -> iguales?([c.pa, c.pb], "Thola") end)

    estado = llamar(c.pa, CpdDoc, :estado)
    assert [{^otro, 3, %{^otro => 2}}] = estado.en_espera
    assert estado.ignoradas == 4
  end
end
