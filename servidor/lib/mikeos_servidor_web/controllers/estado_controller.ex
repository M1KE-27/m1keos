defmodule MikeosServidorWeb.EstadoController do
  @moduledoc """
  La página pública del parque: cuántos equipos hay y con qué versión.

  Es pública a propósito. Si se van a contar equipos, lo justo es que quien
  aporta el dato pueda ver el resultado.
  """
  use MikeosServidorWeb, :controller

  alias MikeosServidor.{Catalogo, Parque}

  def index(conn, _params) do
    render(conn, :index,
      activos: Parque.activos(),
      total: Parque.total(),
      versiones: Parque.por_version(),
      fallos: Parque.fallos_recientes(),
      paises: Parque.paises(),
      ultimas: Catalogo.versiones(),
      layout: false
    )
  end
end
