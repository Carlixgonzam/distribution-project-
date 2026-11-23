defmodule Adhoc.Operaciones do
  def describir(nombres) do
    Enum.filter(catalogo(), fn {nombre, _aridad, _texto} -> nombre in nombres end)
  end

  def ejecutar(propias, nombre, argumentos) do
    if Enum.any?(propias, fn {n, a, _texto} -> n == nombre and a == length(argumentos) end) do
      try do
        apply(__MODULE__, nombre, argumentos)
      rescue
        _error -> {:error, :fallo}
      end
    else
      {:error, :no_existe}
    end
  end

  def eco(valor) do
    {:ok, valor}
  end

  def hora() do
    {:ok, DateTime.to_string(DateTime.truncate(DateTime.utc_now(), :second))}
  end

  def nombre() do
    {:ok, node()}
  end

  def temperatura() do
    case File.read("/sys/class/thermal/thermal_zone0/temp") do
      {:ok, texto} -> {:ok, String.to_integer(String.trim(texto)) / 1000}
      {:error, _razon} -> {:error, :sin_sensor}
    end
  end

  defp catalogo() do
    [
      {:eco, 1, "devuelve el mismo valor"},
      {:hora, 0, "hora UTC del nodo"},
      {:nombre, 0, "nombre Erlang del nodo"},
      {:temperatura, 0, "temperatura de la CPU en grados C"}
    ]
  end
end
