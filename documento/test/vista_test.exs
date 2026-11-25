defmodule CpdDoc.VistaTest do
  use ExUnit.Case, async: true

  alias CpdDoc.Treedoc
  alias CpdDoc.Vista

  @a :"nerves-08f5-c026f1@192.168.1.112"
  @b :"carla@192.168.1.113"

  defp ops() do
    [
      %{op: :ins, from: @a, vc: %{@a => 1}, pos: [{1, 1, @a}], ch: "o"},
      %{op: :ins, from: @b, vc: %{@a => 1, @b => 1}, pos: [{1, 1, @a}, {0, 1, @b}], ch: "h"},
      %{op: :ins, from: @a, vc: %{@a => 2, @b => 1}, pos: [{1, 1, @a}, {1, 2, @a}], ch: "!"},
      %{op: :del, from: @b, vc: %{@a => 2, @b => 2}, pos: [{1, 1, @a}, {1, 2, @a}]}
    ]
  end

  defp estado() do
    %{
      nodo: @a,
      vecinos: [@b],
      reloj: %{@a => 2, @b => 2},
      en_espera: [],
      recibidas: 2,
      duplicadas: 1,
      ignoradas: 0,
      bloqueado: false
    }
  end

  test "el panel muestra el texto, el raw con lápidas y quién hizo cada operación" do
    doc = Enum.reduce(ops(), Treedoc.nuevo(), fn op, d -> Treedoc.aplicar(d, op) end)
    panel = Enum.join(Vista.panel(estado(), doc, ops()), "\n")

    assert panel =~ "nodo      nerves-08f5-c026f1@192.168.1.112"
    assert panel =~ "vecinos   carla@192.168.1.113"
    assert panel =~ "reloj     carla: 2    nerves-08f5-c026f1: 2"
    assert panel =~ "texto     2 caracteres\n  │ ho\n"
    assert panel =~ "raw       3 caracteres, 1 borrados"
    assert panel =~ "[1·1·nerves-08f5-c026f1, 0·1·carla]"
    assert panel =~ ~r/1·2·nerves-08f5-c026f1\]\s+"!"  borrado/
    assert panel =~ "carla #1  insertó \"h\""
    assert panel =~ "carla #2  borró \"!\""
    refute panel =~ "BLOQUEADO"
  end

  test "un documento vacío y una réplica bloqueada se muestran sin fallar" do
    vacio = %{estado() | vecinos: [], reloj: %{}, bloqueado: true}
    panel = Enum.join(Vista.panel(vacio, Treedoc.nuevo(), []), "\n")

    assert panel =~ "vecinos   ninguno"
    assert panel =~ "reloj     vacío"
    assert panel =~ "BLOQUEADO"
    assert panel =~ "texto     0 caracteres\n  │ \n"
    assert panel =~ "  ninguna"
  end

  test "el texto se muestra completo con sus saltos de línea" do
    assert Vista.texto("hola\nmundo") == ["  │ hola", "  │ mundo"]
    assert Vista.texto("") == ["  │ "]
  end

  test "un camino largo se acorta y el raw muestra todos los caracteres" do
    camino = for seq <- 1..300, do: {1, seq, @a}

    assert Vista.camino(camino) ==
             "[… 298 pasos, 1·299·nerves-08f5-c026f1, 1·300·nerves-08f5-c026f1]"

    doc =
      Enum.reduce(1..100, Treedoc.nuevo(), fn seq, d ->
        Treedoc.aplicar(d, %{op: :ins, pos: [{1, seq, @a}], ch: "x"})
      end)

    assert length(Vista.filas(doc)) == 100
    panel = Enum.join(Vista.panel(estado(), doc, []), "\n")
    assert panel =~ "texto     100 caracteres\n  │ " <> String.duplicate("x", 100)
    assert length(Regex.scan(~r/"x"/, panel)) == 100
  end
end
