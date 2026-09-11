defmodule MikeosServidor.Parque do
  @moduledoc """
  El parque de equipos con MIKE OS instalado.

  Sirve para una cosa concreta: enterarse de que una actualización ha roto algo
  **antes** de que alguien se moleste en contarlo. Si publicas una versión y de
  golpe veinte equipos dejan de reportar, o reportan que la instalación falló,
  eso se ve aquí el mismo día.

  Lo que NO es: telemetría. No se guarda quién es nadie.

  * El identificador lo genera el propio equipo al azar la primera vez y vive
    en su disco. No sale de ningún dato del hardware ni de la persona.
  * No se guarda la dirección IP. Se guarda el **país**, que es lo único que
    hace falta para saber si un fallo es de una zona concreta.
  * Es voluntario y viene apagado de fábrica: `m-parque activar`.
  """

  import Ecto.Query, warn: false
  alias MikeosServidor.Repo
  alias MikeosServidor.Parque.Equipo

  @doc """
  Apunta o actualiza lo que dice un equipo.

  Es un *upsert*: el mismo equipo reportando otra vez actualiza su fila en vez
  de crear una nueva. Si no fuera así, un equipo que se actualiza a diario
  parecería treinta equipos al cabo del mes y las cifras no valdrían nada.
  """
  def reportar(atributos) do
    %Equipo{}
    |> Equipo.changeset(Map.put(atributos, "visto_en", DateTime.utc_now(:second)))
    |> Repo.insert(
      on_conflict: {:replace, [:version, :kernel, :arch, :pais, :ultima_actualizacion, :visto_en]},
      conflict_target: :identificador
    )
  end

  @doc "Cuántos equipos hay de cada versión, de más a menos."
  def por_version do
    from(e in Equipo,
      group_by: e.version,
      select: {e.version, count(e.id)},
      order_by: [desc: count(e.id)]
    )
    |> Repo.all()
  end

  @doc """
  Equipos que han dado señales en los últimos treinta días.

  El total a secas engaña: incluye equipos que se formatearon hace medio año.
  """
  def activos(dias \\ 30) do
    corte = DateTime.add(DateTime.utc_now(), -dias * 24 * 3600, :second)
    Repo.aggregate(from(e in Equipo, where: e.visto_en > ^corte), :count)
  end

  @doc "Total histórico de equipos que han reportado alguna vez."
  def total, do: Repo.aggregate(Equipo, :count)

  @doc """
  Actualizaciones que fallaron en los últimos días.

  Es la cifra que de verdad importa: si sube después de publicar algo, hay que
  mirar qué se publicó.
  """
  def fallos_recientes(dias \\ 7) do
    corte = DateTime.add(DateTime.utc_now(), -dias * 24 * 3600, :second)

    from(e in Equipo,
      where: e.visto_en > ^corte and e.ultima_actualizacion == "fallo",
      group_by: e.version,
      select: {e.version, count(e.id)},
      order_by: [desc: count(e.id)]
    )
    |> Repo.all()
  end

  def paises do
    from(e in Equipo,
      where: not is_nil(e.pais),
      group_by: e.pais,
      select: {e.pais, count(e.id)},
      order_by: [desc: count(e.id)],
      limit: 10
    )
    |> Repo.all()
  end
end
