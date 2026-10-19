defmodule BbpartyWeb.PageController do
  use BbpartyWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
