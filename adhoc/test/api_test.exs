defmodule Adhoc.ApiTest do
  use ExUnit.Case, async: false

  alias Adhoc.Api
  alias Adhoc.Mensaje
  alias Adhoc.Operaciones

  setup_all do
    System.cmd("epmd", ["-daemon"])
    Supervisor.terminate_child(Adhoc.Supervisor, Adhoc.Descubrimiento)
    {:ok, _} = Node.start(:"prueba_a@127.0.0.1", name_domain: :longnames)
    Node.set_cookie(:cpd2026)

    b = nodo("prueba_b", "doc", [:eco, :hora])
    c = nodo("prueba_c", "otro", [:eco, :hora, :nombre])

    on_exit(fn ->
      :peer.stop(b.pid)
      :peer.stop(c.pid)
      Node.stop()
      Supervisor.restart_child(Adhoc.Supervisor, Adhoc.Descubrimiento)
    end)

    esperar(fn -> Map.has_key?(Api.apis(), b.nodo) end)
    %{b: b.nodo, c: c.nodo, peer_b: b.pid}
  end

  test "cada nodo aprende la API de los nodos de su dominio y solo de esos", ctx do
    assert Api.apis()[ctx.b] == Operaciones.describir([:eco, :hora])
    refute Map.has_key?(Api.apis(), ctx.c)

    esperar(fn -> Map.has_key?(:erpc.call(ctx.b, Api, :apis, []), node()) end)
    refute Map.has_key?(:erpc.call(ctx.b, Api, :apis, []), ctx.c)
  end

  test "se llama una operación por la API del otro nodo", ctx do
    assert Api.llamar(ctx.b, :eco, [42]) == {:ok, 42}
    assert {:ok, _hora} = Api.llamar(ctx.b, :hora, [])
    assert :erpc.call(ctx.b, Api, :llamar, [node(), :nombre, []]) == {:ok, node()}
  end

  test "lo que el otro nodo no publica no se llama", ctx do
    assert Api.llamar(ctx.b, :nombre, []) == {:error, :no_existe}
    assert Api.llamar(ctx.b, :eco, []) == {:error, :no_existe}
    assert Api.llamar(ctx.c, :eco, [1]) == {:error, :sin_api}
    assert Api.llamar(:"nadie@127.0.0.1", :eco, [1]) == {:error, :sin_api}
  end

  test "el nodo que recibe la llamada también revisa su propia API", ctx do
    send({:adhoc_api, ctx.b}, Mensaje.llamada("doc", self(), :nombre, []))

    assert_receive {:adhoc, 1, :resultado, "doc", de, {:error, :no_existe}}, 2000
    assert de == ctx.b
  end

  test "un mensaje con otro dominio no recibe respuesta", ctx do
    send({:adhoc_api, ctx.c}, Mensaje.llamada("doc", self(), :eco, [1]))
    send({:adhoc_api, ctx.b}, Mensaje.llamada("otro", self(), :eco, [1]))
    send({:adhoc_api, ctx.c}, Mensaje.pregunta("doc", node(), []))

    refute_receive _cualquiera, 500
  end

  test "si el otro nodo no contesta, la llamada termina por timeout", ctx do
    :erpc.call(ctx.b, :sys, :suspend, [:adhoc_api])

    try do
      assert Api.llamar(ctx.b, :eco, [1], 300) == {:error, :timeout}
    after
      :erpc.call(ctx.b, :sys, :resume, [:adhoc_api])
    end

    assert Api.llamar(ctx.b, :eco, [2]) == {:ok, 2}
  end

  test "cuando un nodo se va se olvida su API" do
    d = nodo("prueba_d", "doc", [:eco])

    esperar(fn -> Map.has_key?(Api.apis(), d.nodo) end)
    :peer.stop(d.pid)
    esperar(fn -> not Map.has_key?(Api.apis(), d.nodo) end)

    assert Api.llamar(d.nodo, :eco, [1]) == {:error, :sin_api}
  end

  defp nodo(nombre, dominio, operaciones) do
    {:ok, pid, nodo} =
      :peer.start(%{
        name: String.to_charlist(nombre),
        host: ~c"127.0.0.1",
        longnames: true,
        args: [~c"-setcookie", ~c"cpd2026"]
      })

    :ok = :erpc.call(nodo, :code, :add_paths, [:code.get_path()])
    {:ok, _} = :erpc.call(nodo, :application, :ensure_all_started, [:elixir])
    :erpc.call(nodo, Application, :put_env, [:adhoc, :dominio, dominio])
    :erpc.call(nodo, Application, :put_env, [:adhoc, :operaciones, operaciones])
    {:ok, _} = :erpc.call(nodo, GenServer, :start, [Api, :ok, [name: :adhoc_api]])
    %{pid: pid, nodo: nodo}
  end

  defp esperar(condicion) do
    esperar(condicion, 50)
  end

  defp esperar(condicion, 0) do
    assert condicion.()
  end

  defp esperar(condicion, intentos) do
    if condicion.() do
      :ok
    else
      Process.sleep(100)
      esperar(condicion, intentos - 1)
    end
  end
end
