defmodule MikeosServidor.Catalogo do
  @moduledoc """
  Qué versión es la última de cada paquete.

  Existe para que un equipo pueda preguntar «¿hay algo nuevo?» sin descargarse
  el índice entero del repositorio. Hoy son unos cientos de kilobytes y no
  parece mucho, pero es una descarga por equipo y por comprobación, y sale toda
  por la línea de casa (medida: 780 KB/s de subida). Esta respuesta son unos
  cientos de bytes.

  Lee el mismo `repo.json` que genera `scripts/publicar.sh`. No hay una segunda
  lista que mantener al día: si no existiera este módulo y se copiaran las
  versiones a mano, se quedarían viejas el primer día.
  """

  use GenServer
  require Logger

  @recarga :timer.minutes(5)

  def start_link(opciones), do: GenServer.start_link(__MODULE__, opciones, name: __MODULE__)

  @doc "Mapa de %{\"paquete\" => \"version\"}."
  def versiones, do: GenServer.call(__MODULE__, :versiones)

  @doc "Cuándo se leyó el índice por última vez."
  def leido_en, do: GenServer.call(__MODULE__, :leido_en)

  @impl true
  def init(_) do
    send(self(), :recargar)
    {:ok, %{versiones: %{}, leido_en: nil}}
  end

  @impl true
  def handle_call(:versiones, _de, estado), do: {:reply, estado.versiones, estado}
  def handle_call(:leido_en, _de, estado), do: {:reply, estado.leido_en, estado}

  @impl true
  def handle_info(:recargar, estado) do
    Process.send_after(self(), :recargar, @recarga)

    ruta = Application.get_env(:mikeos_servidor, :repo_json, "/repo/repo.json")

    nuevo =
      case File.read(ruta) do
        {:ok, contenido} ->
          case Jason.decode(contenido) do
            {:ok, datos} ->
              %{estado | versiones: extraer(datos), leido_en: DateTime.utc_now(:second)}

            {:error, motivo} ->
              # Se conserva lo que hubiera: un índice a medio escribir no debe
              # dejar a todos los equipos creyendo que no hay nada publicado.
              Logger.warning("repo.json ilegible (#{inspect(motivo)}); se mantiene el anterior")
              estado
          end

        {:error, :enoent} ->
          Logger.info("todavía no hay repo.json en #{ruta}")
          estado

        {:error, motivo} ->
          Logger.warning("no se pudo leer #{ruta}: #{inspect(motivo)}")
          estado
      end

    {:noreply, nuevo}
  end

  # El índice trae los paquetes en una lista, y el nombre y la versión van
  # dentro de "meta" (junto al sha256 y el nombre de archivo, que aquí no
  # interesan). Se tolera que falte cualquier campo: un paquete raro no debe
  # dejar sin respuesta a todos los equipos.
  #
  # Además se guarda el nombre del archivo, porque es lo que necesita mpm para
  # descargarlo sin volver a pedir el índice entero.
  defp extraer(%{"packages" => paquetes}) when is_list(paquetes) do
    for p <- paquetes,
        meta = Map.get(p, "meta", %{}),
        nombre = Map.get(meta, "name"),
        is_binary(nombre),
        into: %{} do
      {nombre,
       %{
         "version" => Map.get(meta, "version", "?"),
         "release" => Map.get(meta, "release"),
         "archivo" => Map.get(p, "file"),
         "sha256" => Map.get(p, "sha256")
       }}
    end
  end

  defp extraer(_), do: %{}
end
