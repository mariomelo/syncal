defmodule SyncalWeb.PageController do
  use SyncalWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
