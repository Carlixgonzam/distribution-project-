defmodule CpdDoc.Vista do
  alias CpdDoc.Treedoc

  @ultimas 10
  @pasos_visibles 4

  def ver() do
    case CpdDoc.estado() do
      {:error, razon} -> IO.puts("no se pudo leer la réplica: #{inspect(razon)}")
      estado -> IO.puts(Enum.join(panel(estado, CpdDoc.documento(), CpdDoc.historial()), "\n"))
    end
  end

  def raw() do
    case CpdDoc.documento() do
      {:error, razon} -> IO.puts("no se pudo leer la réplica: #{inspect(razon)}")
      doc -> IO.puts(Enum.join(filas(doc), "\n"))
    end
  end

  def mirar(segundos) do
    for _ <- 1..segundos do
      IO.write(IO.ANSI.clear() <> IO.ANSI.home())
      ver()
      Process.sleep(1000)
    end

    :ok
  end

  def panel(estado, doc, historial) do
    [
      "nodo      #{estado.nodo}",
      "vecinos   #{vecinos(estado.vecinos)}",
      "reloj     #{reloj(estado.reloj)}",
      "espera    #{length(estado.en_espera)}    recibidas #{estado.recibidas}    duplicadas #{estado.duplicadas}    ignoradas #{estado.ignoradas}"
    ] ++
      bloqueado(estado.bloqueado) ++
      fuera(Map.get(estado, :fuera, false), Map.get(estado, :descartadas, 0)) ++
      ["", "texto     #{String.length(Treedoc.texto(doc))} caracteres"] ++
      texto(Treedoc.texto(doc)) ++
      [
        "",
        "raw       #{map_size(doc.atomos)} caracteres, #{MapSet.size(doc.borrados)} borrados, en orden"
      ] ++
      filas(doc) ++
      ["", "últimas operaciones"] ++
      operaciones(Enum.take(historial, -@ultimas), doc)
  end

  def texto(texto) do
    Enum.map(String.split(texto, "\n"), fn linea -> "  │ " <> linea end)
  end

  def filas(doc) do
    Enum.map(Treedoc.orden(doc), fn {posid, caracter} -> fila(posid, caracter, doc.borrados) end)
  end

  def camino(posid) do
    if length(posid) > @pasos_visibles do
      "[… #{length(posid) - 2} pasos, #{pasos(Enum.take(posid, -2))}]"
    else
      "[#{pasos(posid)}]"
    end
  end

  def corto(nodo) do
    hd(String.split(to_string(nodo), "@"))
  end

  defp fila(posid, caracter, borrados) do
    if MapSet.member?(borrados, posid) do
      "  #{String.pad_trailing(camino(posid), 44)} #{inspect(caracter)}  borrado"
    else
      "  #{String.pad_trailing(camino(posid), 44)} #{inspect(caracter)}"
    end
  end

  defp pasos(posid) do
    Enum.map_join(posid, ", ", fn {bit, seq, nodo} -> "#{bit}·#{seq}·#{corto(nodo)}" end)
  end

  defp vecinos([]) do
    "ninguno"
  end

  defp vecinos(nodos) do
    Enum.map_join(Enum.sort(nodos), ", ", fn nodo -> to_string(nodo) end)
  end

  defp reloj(vc) when map_size(vc) == 0 do
    "vacío"
  end

  defp reloj(vc) do
    Enum.map_join(Enum.sort(vc), "    ", fn {nodo, n} -> "#{corto(nodo)}: #{n}" end)
  end

  defp bloqueado(true) do
    [
      "BLOQUEADO  el historial estaba dañado: reinicia el nodo con otro nombre para volver a editar"
    ]
  end

  defp bloqueado(_) do
    []
  end

  defp fuera(true, descartadas) do
    [
      "FUERA DE LÍNEA  no envía ni recibe (#{descartadas} descartadas); edita local y vuelve con CpdDoc.unirse()"
    ]
  end

  defp fuera(_, _) do
    []
  end

  defp operaciones([], _doc) do
    ["  ninguna"]
  end

  defp operaciones(ops, doc) do
    Enum.map(ops, fn op -> "  #{corto(op.from)} ##{op.vc[op.from]}  #{accion(op, doc)}" end)
  end

  defp accion(%{op: :ins, ch: caracter}, _doc) do
    "insertó #{inspect(caracter)}"
  end

  defp accion(%{op: :del, pos: posid}, doc) do
    "borró #{inspect(Map.get(doc.atomos, posid))}"
  end
end
