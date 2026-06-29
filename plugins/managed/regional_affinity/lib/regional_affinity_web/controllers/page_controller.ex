defmodule RegionalAffinityWeb.PageController do
  use RegionalAffinityWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
