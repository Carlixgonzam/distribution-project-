defmodule CpdDoc.Historial do
  alias CpdDoc.Mensaje

  def abrir(archivo) do
    with :ok <- File.mkdir_p(Path.dirname(archivo)),
         :ok <- cortar_linea_incompleta(archivo) do
      :file.open(archivo, [:append, :binary, :raw])
    end
  end

  def cargar(archivo) do
    case File.read(archivo) do
      {:ok, datos} -> leer_lineas(String.split(datos, "\n", trim: true), 1, [])
      {:error, :enoent} -> {:ok, []}
      {:error, razon} -> {:error, razon}
    end
  end

  def agregar(_fd, []) do
    :ok
  end

  def agregar(fd, ops) do
    lineas = Enum.map(ops, fn op -> [Base.encode64(:erlang.term_to_binary(op)), ?\n] end)

    with :ok <- :file.write(fd, lineas) do
      :file.sync(fd)
    end
  end

  def apartar(archivo, prefijo) do
    with :ok <- File.rename(archivo, "#{archivo}.danado-#{System.os_time(:second)}"),
         {:ok, fd} <- abrir(archivo),
         :ok <- agregar(fd, prefijo) do
      {:ok, fd}
    end
  end

  defp leer_lineas([], _n, ops) do
    {:ok, Enum.reverse(ops)}
  end

  defp leer_lineas([linea | resto], n, ops) do
    case decodificar(linea) do
      {:ok, op} -> leer_lineas(resto, n + 1, [op | ops])
      :error -> {:corrupto, Enum.reverse(ops), n}
    end
  end

  defp decodificar(linea) do
    with {:ok, binario} <- Base.decode64(linea) do
      Mensaje.leer(:erlang.binary_to_term(binario))
    end
  rescue
    ArgumentError -> :error
  end

  defp cortar_linea_incompleta(archivo) do
    case File.read(archivo) do
      {:ok, datos} -> cortar(archivo, datos)
      {:error, _} -> :ok
    end
  end

  defp cortar(archivo, datos) do
    if datos == "" or String.ends_with?(datos, "\n") do
      :ok
    else
      truncar(archivo, despues_del_ultimo_salto(datos))
    end
  end

  defp despues_del_ultimo_salto(datos) do
    case :binary.matches(datos, "\n") do
      [] ->
        0

      saltos ->
        {posicion, _} = List.last(saltos)
        posicion + 1
    end
  end

  defp truncar(archivo, posicion) do
    with {:ok, f} <- :file.open(archivo, [:read, :write, :binary, :raw]),
         {:ok, _} <- :file.position(f, posicion),
         :ok <- :file.truncate(f),
         :ok <- :file.sync(f) do
      :file.close(f)
    end
  end
end
