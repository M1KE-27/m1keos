defmodule MikeosServidorWeb.Router do
  use MikeosServidorWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MikeosServidorWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", MikeosServidorWeb do
    pipe_through :browser

    # La página pública del parque. Es pública a propósito: si se van a contar
    # equipos, quien aporta el dato tiene derecho a ver el resultado.
    get "/estado", EstadoController, :index
  end

  scope "/api", MikeosServidorWeb do
    pipe_through :api

    # Lo que consulta un MIKE OS para saber si hay algo nuevo, sin bajarse el
    # índice entero del repositorio.
    get "/version", ApiController, :version
    # Lo que manda un equipo si su dueño ha activado el reporte anónimo.
    post "/equipos", ApiController, :reportar
  end
end
