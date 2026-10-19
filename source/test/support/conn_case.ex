defmodule BbpartyWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint BbpartyWeb.Endpoint

      use BbpartyWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import BbpartyWeb.ConnCase
    end
  end

  setup tags do
    Bbparty.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
