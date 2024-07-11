defmodule HomeController do
  def serve_homepage(conn, %{csrf_token: token}) do
    html = EEx.eval_file("./priv/index.html.heex", csrf_token: token)
    Plug.Conn.send_resp(conn, 200, html)
  end

	def serve_js(conn, _) do
		Plug.Conn.send_file(conn, 200, "priv/main.js")
	end

  def serve_hls(conn, %{"file" => file}) do
    path = Path.join("priv/hls", file)
    if File.exists?(path) do
      Plug.Conn.send_file(conn, 200, path)
    else
      Plug.Conn.send_resp(conn, 404, "File not found")
    end
  end
end
