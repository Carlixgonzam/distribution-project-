defmodule CpdDoc.ReplicaTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias CpdDoc.Historial

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    archivo = Path.join(dir, "r.log")
    Application.put_env(:cpd_doc, :historial, archivo)
    on_exit(fn -> Application.delete_env(:cpd_doc, :historial) end)
    %{archivo: archivo}
  end

  defp op(seq, ch) do
    %{op: :ins, from: :x, vc: %{x: seq}, pos: [{1, seq, :x}], ch: ch}
  end

  test "la vista se imprime con y sin réplica" do
    assert capture_io(fn -> CpdDoc.ver() end) =~ "no se pudo leer la réplica: :sin_replica"
    assert capture_io(fn -> CpdDoc.raw() end) =~ "no se pudo leer la réplica: :sin_replica"

    start_supervised!(CpdDoc.Replica)

    assert CpdDoc.documento() == CpdDoc.Treedoc.nuevo()
    assert capture_io(fn -> CpdDoc.ver() end) =~ "texto     0 caracteres"
    assert capture_io(fn -> CpdDoc.raw() end) == "\n"
  end

  test "sin red se lee pero no se edita, y ninguna entrada inválida la tumba" do
    pid = start_supervised!(CpdDoc.Replica)

    assert CpdDoc.insertar(0, "x") == {:error, :sin_red}
    assert CpdDoc.texto() == ""
    assert CpdDoc.borrar(0) == {:error, :posicion_invalida}
    assert CpdDoc.borrar(-1, 2) == {:error, :posicion_invalida}
    assert CpdDoc.borrar("0", 1) == {:error, :posicion_invalida}
    assert CpdDoc.insertar(0, 5) == {:error, :argumentos_invalidos}
    assert CpdDoc.insertar(0, <<255>>) == {:error, :texto_invalido}
    assert CpdDoc.insertar(0, "") == :ok
    assert GenServer.call(Crdt.Replica, :lo_que_sea) == {:error, :desconocida}
    assert GenServer.call(Crdt.Replica, {:local, :raro}) == {:error, :argumentos_invalidos}
    assert CpdDoc.conectar(123) == {:error, :nodo_invalido}

    for _ <- 1..3_000 do
      m = CpdDoc.Azar.mensaje()
      GenServer.cast(Crdt.Replica, m)
      send(Crdt.Replica, m)
    end

    assert CpdDoc.texto() == ""
    assert Process.whereis(Crdt.Replica) == pid
    assert CpdDoc.estado().ignoradas > 0
  end

  test "aplica lo que llega en orden causal aunque llegue desordenado" do
    start_supervised!(CpdDoc.Replica)

    GenServer.cast(Crdt.Replica, {:remote, op(2, "o")})
    assert CpdDoc.texto() == ""
    assert [{:x, 2, %{x: 1}}] = CpdDoc.estado().en_espera

    GenServer.cast(Crdt.Replica, {:remote, op(1, "h")})
    GenServer.cast(Crdt.Replica, {:remote, op(1, "h")})
    assert CpdDoc.texto() == "ho"
    assert CpdDoc.estado().en_espera == []
    assert CpdDoc.estado().duplicadas == 1
  end

  test "fuera de línea descarta lo remoto, sigue así tras reiniciar, y al unirse vuelve", %{
    archivo: archivo
  } do
    start_supervised!(CpdDoc.Replica)
    GenServer.cast(Crdt.Replica, {:remote, op(1, "h")})
    assert CpdDoc.texto() == "h"

    assert CpdDoc.unirse() == :ok
    refute CpdDoc.estado().fuera

    assert CpdDoc.salir() == :ok
    assert CpdDoc.estado().fuera
    assert File.exists?(archivo <> ".fuera")

    GenServer.cast(Crdt.Replica, {:remote, op(2, "i")})
    assert CpdDoc.texto() == "h"
    assert CpdDoc.estado().descartadas == 1
    assert CpdDoc.estado().reloj == %{x: 1}

    stop_supervised!(CpdDoc.Replica)
    start_supervised!(CpdDoc.Replica)
    assert CpdDoc.estado().fuera
    assert CpdDoc.texto() == "h"

    assert CpdDoc.unirse() == :ok
    refute CpdDoc.estado().fuera
    refute File.exists?(archivo <> ".fuera")
    GenServer.cast(Crdt.Replica, {:remote, op(2, "i")})
    assert CpdDoc.texto() == "hi"
  end

  test "si no puede guardar una operación remota no la aplica (llegará otra vez)", %{
    archivo: archivo
  } do
    pid = start_supervised!(CpdDoc.Replica)
    {:ok, salida} = StringIO.open("")
    Process.group_leader(pid, salida)
    GenServer.cast(Crdt.Replica, {:remote, op(1, "h")})
    assert CpdDoc.texto() == "h"

    :sys.replace_state(Crdt.Replica, fn e ->
      :file.close(e.fd)
      e
    end)

    GenServer.cast(Crdt.Replica, {:remote, op(2, "i")})
    assert CpdDoc.texto() == "h"
    assert elem(StringIO.contents(salida), 1) =~ "no se pudo guardar"
    assert CpdDoc.estado().reloj == %{x: 1}

    :sys.replace_state(Crdt.Replica, fn e ->
      {:ok, fd} = Historial.abrir(archivo)
      %{e | fd: fd}
    end)

    GenServer.cast(Crdt.Replica, {:remote, op(2, "i")})
    assert CpdDoc.texto() == "hi"
  end

  test "al reiniciar reconstruye texto y reloj desde el log" do
    start_supervised!(CpdDoc.Replica)
    GenServer.cast(Crdt.Replica, {:remote, op(1, "h")})
    GenServer.cast(Crdt.Replica, {:remote, op(2, "i")})
    assert CpdDoc.texto() == "hi"

    stop_supervised!(CpdDoc.Replica)
    start_supervised!(CpdDoc.Replica)

    assert CpdDoc.texto() == "hi"
    assert CpdDoc.estado().reloj == %{x: 2}
    assert length(CpdDoc.historial()) == 2
  end

  test "con el log dañado en medio arranca con el prefijo válido", %{archivo: archivo} do
    {:ok, fd} = Historial.abrir(archivo)
    :ok = Historial.agregar(fd, [op(1, "h")])
    File.write!(archivo, "basura\n", [:append])
    :ok = Historial.agregar(fd, [op(2, "i")])

    salida = capture_io(fn -> start_supervised!(CpdDoc.Replica) end)

    assert salida =~ "historial dañado en la línea 2"
    assert CpdDoc.texto() == "h"
    assert CpdDoc.estado().bloqueado == false
    assert [_] = Path.wildcard(archivo <> ".danado-*")
  end

  test "si no puede abrir el log no arranca y las llamadas responden sin_replica" do
    Application.put_env(:cpd_doc, :historial, "/dev/null/no/se/puede/r.log")

    salida = capture_io(fn -> start_supervised(CpdDoc.Replica) end)

    assert salida =~ "réplica no iniciada"
    assert Process.whereis(Crdt.Replica) == nil
    assert CpdDoc.texto() == {:error, :sin_replica}
    assert CpdDoc.insertar(0, "x") == {:error, :sin_replica}
  end
end
