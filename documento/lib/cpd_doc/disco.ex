defmodule CpdDoc.Disco do
  # Guarda el contenido del documento (atomos y borrados) para que sobreviva si se
  # apagan todos los nodos a la vez. El archivo es el mismo mensaje del protocolo,
  # así que al cargarlo pasa por la misma validación que un mensaje recibido.
  # No se guardan contador ni encarnación: la réplica arranca con una encarnación
  # nueva, así que un archivo desactualizado nunca hace repetir un PosID.

  alias CpdDoc.Protocolo
  alias CpdDoc.Treedoc

  def cargar(nil) do
    Treedoc.vacio()
  end

  def cargar(archivo) do
    with {:ok, binario} <- File.read(archivo),
         {:ok, doc} <- Protocolo.leer(decodificar(binario)) do
      doc
    else
      _ -> Treedoc.vacio()
    end
  end

  def guardar(nil, _doc) do
    :ok
  end

  def guardar(archivo, doc) do
    temporal = archivo <> ".tmp"
    binario = :erlang.term_to_binary(Protocolo.mensaje(doc), [:compressed])

    with :ok <- File.mkdir_p(Path.dirname(archivo)),
         :ok <- File.write(temporal, binario),
         :ok <- File.rename(temporal, archivo) do
      :ok
    end
  end

  defp decodificar(binario) do
    :erlang.binary_to_term(binario)
  rescue
    ArgumentError -> :corrupto
  end
end
