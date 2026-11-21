defmodule Proyectodistribu.Treedoc do
  def vacio() do
    %{atomos: %{}, borrados: MapSet.new()}
  end

  def nuevo() do
    Map.put(vacio(), :contador, 0)
  end

  def menor?([], []) do
    false
  end

  def menor?([], [{bit, _} | _]) do
    bit == 1
  end

  # ... aquí sigues con el resto de funciones
end
