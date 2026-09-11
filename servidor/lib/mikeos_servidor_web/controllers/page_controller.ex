defmodule MikeosServidorWeb.PageController do
  use MikeosServidorWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
