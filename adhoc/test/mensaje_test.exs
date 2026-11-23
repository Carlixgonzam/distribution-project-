defmodule Adhoc.MensajeTest do
  use ExUnit.Case, async: true

  alias Adhoc.Mensaje
  alias Adhoc.Operaciones

  test "los cuatro mensajes se leen de vuelta" do
    operaciones = Operaciones.describir([:eco, :hora])
    nodo = :"doc@172.20.10.3"

    assert Mensaje.leer(Mensaje.pregunta("doc", nodo, operaciones)) ==
             {:api?, "doc", nodo, operaciones}

    assert Mensaje.leer(Mensaje.respuesta("doc", nodo, operaciones)) ==
             {:api, "doc", nodo, operaciones}

    assert Mensaje.leer(Mensaje.llamada("doc", self(), :eco, [1])) ==
             {:llamar, "doc", self(), :eco, [1]}

    assert Mensaje.leer(Mensaje.resultado("doc", nodo, {:ok, 1})) ==
             {:resultado, "doc", nodo, {:ok, 1}}
  end

  test "mensajes mal formados se descartan enteros" do
    nodo = :"doc@172.20.10.3"

    assert Mensaje.leer({:adhoc, 2, :api?, "doc", nodo, []}) == :error
    assert Mensaje.leer({:adhoc, 1, :api?, :doc, nodo, []}) == :error
    assert Mensaje.leer({:adhoc, 1, :api, "doc", "doc@x", []}) == :error
    assert Mensaje.leer({:adhoc, 1, :api, "doc", nodo, [{:eco, -1, "x"}]}) == :error
    assert Mensaje.leer({:adhoc, 1, :api, "doc", nodo, [{:eco, 1, :x}]}) == :error
    assert Mensaje.leer({:adhoc, 1, :api, "doc", nodo, [{:eco, 1, "x"} | :cola]}) == :error
    assert Mensaje.leer({:adhoc, 1, :llamar, "doc", :no_pid, :eco, [1]}) == :error
    assert Mensaje.leer({:adhoc, 1, :llamar, "doc", self(), :eco, [1 | 2]}) == :error
    assert Mensaje.leer({:adhoc, 1, :resultado, "doc", nodo, 42}) == :error
    assert Mensaje.leer({:cpd, 1, nodo, {:estado, [], []}}) == :error
    assert Mensaje.leer(:hola) == :error
  end

  test "solo se publican operaciones que existen" do
    assert Operaciones.describir([:eco, :no_existe]) == [{:eco, 1, "devuelve el mismo valor"}]
  end

  test "una operación solo se ejecuta si el nodo la publica con esa aridad" do
    propias = Operaciones.describir([:eco, :hora])

    assert Operaciones.ejecutar(propias, :eco, [7]) == {:ok, 7}
    assert Operaciones.ejecutar(propias, :eco, []) == {:error, :no_existe}
    assert Operaciones.ejecutar(propias, :nombre, []) == {:error, :no_existe}
    assert Operaciones.ejecutar(propias, :describir, [[:eco]]) == {:error, :no_existe}
    assert {:ok, _hora} = Operaciones.ejecutar(propias, :hora, [])
  end

  test "sin sensor la temperatura da error en vez de caerse" do
    if File.exists?("/sys/class/thermal/thermal_zone0/temp") do
      assert {:ok, _grados} = Operaciones.temperatura()
    else
      assert Operaciones.temperatura() == {:error, :sin_sensor}
    end
  end
end
