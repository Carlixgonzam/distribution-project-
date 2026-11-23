defmodule CpdDoc.Replica do
  use GenServer

  alias CpdDoc.Disco
  alias CpdDoc.Protocolo
  alias CpdDoc.Treedoc

  @guardar_cada 5_000

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
    Process.send_after(self(), :guardar, @guardar_cada)
    archivo = Application.get_env(:cpd_doc, :archivo)

    {:ok,
     %{
       doc: Treedoc.merge(Treedoc.nuevo(), Disco.cargar(archivo)),
       encarnacion: :rand.uniform(1_000_000_000),
       archivo: archivo,
       sucio: false
     }}
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
      {:ok, delta} -> {:noreply, cambiar(estado, Treedoc.merge(estado.doc, delta))}
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

  def handle_info(:guardar, estado) do
    Process.send_after(self(), :guardar, @guardar_cada)

    if estado.sucio do
      case Disco.guardar(estado.archivo, estado.doc) do
        :ok ->
          {:noreply, %{estado | sucio: false}}

        {:error, razon} ->
          IO.puts("no se pudo guardar el documento: #{inspect(razon)}")
          {:noreply, estado}
      end
    else
      {:noreply, estado}
    end
  end

  def handle_info(_otro, estado) do
    {:noreply, estado}
  end

  defp aplicar_local({:error, razon}, estado) do
    {:reply, {:error, razon}, estado}
  end

  defp aplicar_local({doc, delta}, estado) do
    Protocolo.difundir(delta)
    {:reply, :ok, cambiar(estado, doc)}
  end

  defp cambiar(estado, doc) do
    cambio = doc.atomos != estado.doc.atomos or doc.borrados != estado.doc.borrados
    %{estado | doc: doc, sucio: estado.sucio or cambio}
  end
end
