defmodule DncWatchdogWeb.SecurityHeadersTest do
  use DncWatchdogWeb.ConnCase, async: true

  test "browser responses include a CSP that allows LiveView, fonts, and websockets", %{
    conn: conn
  } do
    conn = get(conn, ~p"/")
    csp = get_resp_header(conn, "content-security-policy") |> List.first()

    assert csp
    assert csp =~ ~r/default-src 'self'/
    assert csp =~ ~r/script-src[^;]*'self'/
    assert csp =~ ~r/style-src[^;]*https:\/\/fonts\.googleapis\.com/
    assert csp =~ ~r/font-src[^;]*https:\/\/fonts\.gstatic\.com/
    assert csp =~ ~r/connect-src[^;]*ws:/
    assert csp =~ ~r/connect-src[^;]*wss:/
    assert csp =~ ~r/connect-src[^;]*https:\/\/fonts\.googleapis\.com/
    assert csp =~ ~r/connect-src[^;]*https:\/\/fonts\.gstatic\.com/
  end

  test "production endpoint config enables HSTS via force_ssl" do
    config = Config.Reader.read!("config/prod.exs", env: :prod)
    endpoint = get_in(config, [:dnc_watchdog, DncWatchdogWeb.Endpoint])

    assert Keyword.get(endpoint, :force_ssl) == [hsts: true]
  end
end
