defmodule MikeosServidor.Repo.Migrations.CrearEquipos do
  use Ecto.Migration

  def change do
    create table(:equipos) do
      add :identificador, :string, null: false
      add :version, :string, null: false
      add :kernel, :string
      add :arch, :string
      add :pais, :string, size: 2
      add :ultima_actualizacion, :string
      add :visto_en, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    # Único porque el mismo equipo reportando dos veces tiene que actualizar su
    # fila, no crear otra: si no, un equipo que se actualiza a diario parecería
    # treinta equipos al mes.
    create unique_index(:equipos, [:identificador])
    # Las consultas del panel son siempre "los de los últimos N días".
    create index(:equipos, [:visto_en])
  end
end
