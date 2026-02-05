defmodule ExGoCDWeb.PageController do
  use ExGoCDWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
