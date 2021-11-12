defmodule BlockScoutWeb.CSPHeader do
  @moduledoc """
  Plug to set content-security-policy with websocket endpoints
  """

  alias Phoenix.Controller
  alias Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    Controller.put_secure_browser_headers(conn, %{
      "content-security-policy" => "\
        connect-src 'self' #{websocket_endpoints(conn)} https://www.google-analytics.com/ *.poa.network https://request-global.czilladx.com https://raw.githubusercontent.com/trustwallet/assets/ https://stats.g.doubleclick.net/ app.pendo.io pendo-io-static.storage.googleapis.com cdn.pendo.io pendo-static-SUB_ID.storage.googleapis.com data.pendo.io; \
        default-src 'self';\
        script-src 'self' 'unsafe-inline' 'unsafe-eval' https://www.google.com https://www.googletagmanager.com https://www.google-analytics.com/ https://www.gstatic.com *.hcaptcha.com https://assets.hcaptcha.com https://coinzillatag.com *.pendo.io https://pendo-io-static.storage.googleapis.com/;\
        style-src 'self' 'unsafe-inline' 'unsafe-eval' https://fonts.googleapis.com app.pendo.io cdn.pendo.io pendo-static-SUB_ID.storage.googleapis.com;\
        img-src 'self' * data: cdn.pendo.io app.pendo.io pendo-static-SUB_ID.storage.googleapis.com data.pendo.io;\
        media-src 'self' * data:;\
        font-src 'self' 'unsafe-inline' 'unsafe-eval' https://fonts.gstatic.com data:;\
        frame-ancestors app.pendo.io;\
        frame-src 'self' 'unsafe-inline' 'unsafe-eval' https://www.google.com *.hcaptcha.com https://request-global.czilladx.com/ app.pendo.io;\
        child-src app.pendo.io;\
      "
    })
  end

  defp websocket_endpoints(conn) do
    host = Conn.get_req_header(conn, "host")
    "ws://#{host} wss://#{host}"
  end
end
