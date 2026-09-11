defmodule MikeosServidorWeb.EstadoHTML do
  @moduledoc """
  La página del parque.

  Se escribe aquí en vez de usar una plantilla aparte porque es una sola
  página, y con los mismos cinco colores que el escritorio y el resto del sitio
  (ver `quickshell/Paleta.qml`): el sistema y su web tienen que parecer la
  misma cosa.
  """
  use MikeosServidorWeb, :html

  def index(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="es">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width,initial-scale=1" />
        <title>Estado del parque · MIKE OS</title>
        <link rel="stylesheet" href="/estilo.css" />
        <style>
          .barra{height:8px;border-radius:4px;background:var(--acento);min-width:3px}
          .fila{display:grid;grid-template-columns:1fr 3fr auto;gap:12px;
                align-items:center;padding:9px 0;border-bottom:1px solid var(--borde)}
          .fila span:first-child{font:13px ui-monospace,Menlo,monospace}
          .aviso-fallo{border-left-color:var(--aviso,#e3a13c)}
        </style>
      </head>
      <body>
        <nav>
          <div class="cont">
            <a class="marca" href="/">MIKE OS</a>
            <a class="enl" href="/">Inicio</a>
            <a class="enl" href="/descargas.html">Descargar</a>
            <a class="enl" href="/docs/index.html">Documentación</a>
            <a class="enl aqui" href="/estado">Estado</a>
          </div>
        </nav>

        <div class="cont">
          <header>
            <h1>Estado del parque</h1>
            <p class="lema">
              Cuántos equipos llevan MIKE OS y con qué versión. Lo reportan ellos,
              de forma anónima y sólo si su dueño lo ha activado.
            </p>
          </header>

          <div class="cifras">
            <div class="cifra">
              <b>{@activos}</b><span>activos (30 días)</span>
            </div>
            <div class="cifra">
              <b>{@total}</b><span>han reportado alguna vez</span>
            </div>
            <div class="cifra">
              <b>{length(@versiones)}</b><span>versiones distintas</span>
            </div>
          </div>

          <h2>Versiones en uso</h2>
          <%= if @versiones == [] do %>
            <p class="tenue">Todavía no ha reportado ningún equipo.</p>
          <% else %>
            <div :for={{version, cuantos} <- @versiones} class="fila">
              <span>{version}</span>
              <div class="barra" style={"width:#{porcentaje(cuantos, @total)}%"}></div>
              <span class="tenue">{cuantos}</span>
            </div>
          <% end %>

          <h2>Actualizaciones que fallaron (7 días)</h2>
          <%= if @fallos == [] do %>
            <p class="tenue">Ninguna. Es la cifra que conviene mirar después de publicar algo.</p>
          <% else %>
            <div class="aviso aviso-fallo">
              <p>
                <strong>Ojo:</strong> hay equipos con actualizaciones fallidas.
                Si esto sube justo después de publicar, mira qué se publicó.
              </p>
            </div>
            <div :for={{version, cuantos} <- @fallos} class="fila">
              <span>{version}</span>
              <div></div>
              <span class="tenue">{cuantos}</span>
            </div>
          <% end %>

          <h2>Lo último publicado</h2>
          <table>
            <tr><th>Paquete</th><th>Versión</th></tr>
            <tr :for={{paquete, datos} <- Enum.sort(@ultimas)}>
              <td>{paquete}</td>
              <td>{datos["version"]}</td>
            </tr>
          </table>

          <h2>Qué se guarda</h2>
          <ul>
            <li>Un identificador <strong>al azar</strong> que genera tu propio equipo.
              No sale del hardware ni de ti.</li>
            <li>La versión de MIKE OS, la del kernel y la arquitectura.</li>
            <li>Si la última actualización fue bien o mal.</li>
            <li>El país. <strong>La dirección IP no se guarda.</strong></li>
          </ul>
          <p class="tenue">
            Viene apagado de fábrica. Se activa con <code>m-parque activar</code> y se
            quita con <code>m-parque desactivar</code>, que además borra tu fila.
          </p>

          <footer>MIKE OS · <a href="/">Inicio</a></footer>
        </div>
      </body>
    </html>
    """
  end

  # Con un solo equipo la barra saldría siempre al 100 %, que no dice nada;
  # y sin equipos habría que dividir entre cero.
  defp porcentaje(_cuantos, 0), do: 0
  defp porcentaje(cuantos, total), do: round(cuantos * 100 / total)
end
