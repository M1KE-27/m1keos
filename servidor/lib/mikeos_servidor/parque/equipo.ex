defmodule MikeosServidor.Parque.Equipo do
  @moduledoc """
  Un equipo con MIKE OS que ha dicho qué versión lleva.

  Cada campo está aquí porque sirve para decidir algo. Lo que no sirva para
  decidir nada no se guarda: es lo que separa saber si una actualización rompió
  algo de vigilar a la gente.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "equipos" do
    # Generado al azar por el propio equipo. No sale del hardware ni de nadie.
    field :identificador, :string
    field :version, :string
    field :kernel, :string
    field :arch, :string
    # Sólo el país, nunca la IP: basta para ver si un fallo es de una zona.
    field :pais, :string
    # "ok" | "fallo" | nil
    field :ultima_actualizacion, :string
    field :visto_en, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(equipo, atributos) do
    equipo
    |> cast(atributos, [
      :identificador, :version, :kernel, :arch, :pais, :ultima_actualizacion, :visto_en
    ])
    |> validate_required([:identificador, :version])
    # El identificador lo manda el cliente, así que se valida la forma: 32
    # caracteres hexadecimales y nada más. Sin esto, cualquiera podría mandar
    # texto arbitrario y usarlo para meter datos que no deberían estar aquí.
    |> validate_format(:identificador, ~r/^[0-9a-f]{32}$/)
    |> validate_length(:version, max: 64)
    |> validate_length(:kernel, max: 96)
    |> validate_inclusion(:arch, ["x86_64", "aarch64"])
    |> validate_inclusion(:ultima_actualizacion, ["ok", "fallo"])
    |> validate_length(:pais, max: 2)
    |> unique_constraint(:identificador)
  end
end
