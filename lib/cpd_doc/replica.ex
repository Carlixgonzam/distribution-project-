defmodule CpdDoc.Replica do
  use GenServer

  alias CpdDoc.Protocolo
  alias CpdDoc.Treedoc

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: :cpd_doc)
  end

  def insertar(i, caracter) do
    GenServer.call(:cpd_doc, {:insertar, i, caracter})
  end

  def borrar(i) do
    GenServer.call(:cpd_doc, {:borrar, i})
  end

  def texto() do
    GenServer.call(:cpd_doc, :texto)
  end

  def init(:ok) do
    :net_kernel.monitor_nodes(true)
    Process.send_after(self(), :difundir, 30_000)
    {:ok, %{doc: Treedoc.nuevo(), encarnacion: :rand.uniform(1_000_000_000)}}
  end

  def handle_call({:insertar, i, caracter}, _de, estado) do
    sitio = {node(), estado.encarnacion}
    aplicar_local(Treedoc.insertar(estado.doc, i, caracter, sitio), estado)
  end

  def handle_call({:borrar, i}, _de, estado) do
    aplicar_local(Treedoc.borrar(estado.doc, i), estado)
  end

  def handle_call(:texto, _de, estado) do
    {:reply, Treedoc.texto(estado.doc), estado}
  end

  def handle_cast(mensaje, estado) do
    handle_info(mensaje, estado)
  end

  def handle_info({:cpd, version, origen, cuerpo}, estado) do
    case Protocolo.leer({:cpd, version, origen, cuerpo}) do
      {:ok, delta} -> {:noreply, %{estado | doc: Treedoc.merge(estado.doc, delta)}}
      :error -> {:noreply, estado}
    end
  end

  def handle_info({:nodeup, _nodo}, estado) do
    Protocolo.difundir(estado.doc)
    {:noreply, estado}
  end

  def handle_info(:difundir, estado) do
    Protocolo.difundir(estado.doc)
    Process.send_after(self(), :difundir, 30_000)
    {:noreply, estado}
  end

  def handle_info(_otro, estado) do
    {:noreply, estado}
  end

  defp aplicar_local({:error, razon}, estado) do
    {:reply, {:error, razon}, estado}
  end

  defp aplicar_local({doc, delta}, estado) do
    Protocolo.difundir(delta)
    {:reply, :ok, %{estado | doc: doc}}
  end
end
