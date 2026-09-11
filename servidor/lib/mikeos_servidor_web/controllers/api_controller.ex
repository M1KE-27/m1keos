defmodule MikeosServidorWeb.ApiController do
  @moduledoc """
  Lo que consultan los equipos con MIKE OS.

  Dos cosas y ninguna más. Una API que hace pocas cosas se puede explicar, y
  sobre todo se puede apagar sin que nada se rompa: si este servidor se cae, un
  MIKE OS sigue funcionando igual. Sólo deja de saber si hay novedades.
  """
  use MikeosServidorWeb, :controller

  alias MikeosServidor.{Catalogo, Parque}

  @doc """
  GET /api/version — la última versión de cada paquete.

  Unos cientos de bytes, en vez del índice entero del repositorio.
  """
  def version(conn, _params) do
    json(conn, %{
      paquetes: Catalogo.versiones(),
      leido_en: Catalogo.leido_en()
    })
  end

  @doc """
  POST /api/equipos — un equipo dice qué versión lleva.

  Voluntario y apagado de fábrica (`m-parque activar`). Del cuerpo sólo se
  mira lo que está declarado en el esquema; cualquier otra cosa se descarta,
  para que nadie pueda usar esto de almacén.
  """
  def reportar(conn, params) do
    atributos =
      params
      |> Map.take(["identificador", "version", "kernel", "arch", "ultima_actualizacion"])
      |> Map.put("pais", pais(conn))

    case Parque.reportar(atributos) do
      {:ok, _equipo} ->
        json(conn, %{estado: "ok"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{estado: "rechazado", motivos: errores(changeset)})
    end
  end

  # El país lo pone Cloudflare o el proxy si está delante; si no hay, se queda
  # sin país. Nunca se deduce de la IP aquí, porque eso obligaría a guardarla.
  defp pais(conn) do
    case Plug.Conn.get_req_header(conn, "cf-ipcountry") do
      [codigo | _] when byte_size(codigo) == 2 -> String.upcase(codigo)
      _ -> nil
    end
  end

  defp errores(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {mensaje, _opciones} -> mensaje end)
  end
end
