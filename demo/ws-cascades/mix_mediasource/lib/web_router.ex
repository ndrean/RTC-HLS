defmodule WebRouter do
	use Plug.Router

	@session_options [
		store: :cookie, key: "_my_key", signing_salt: "my_salt", table: :session,
		secret_key_base: String.duplicate("a", 64)
	]

	plug Plug.Session, @session_options
	plug :fetch_session
	plug Plug.CSRFProtection
	plug(:match)
  plug(:dispatch)


	get "/" do
    Plug.Conn.put_resp_header(conn,"x-frame-options","ALLOW-FROM https://example.com")
		token = Plug.CSRFProtection.get_csrf_token()

		conn
		|> Plug.Conn.fetch_session()
		|> Plug.Conn.put_session(:csrf_token, token)
		
		HomeController.serve_homepage(conn, %{csrf_token: token})
	end

	get "/js/main.js" do
		HomeController.serve_js(conn, [])
	end

  get "/hls/:file" do
		IO.puts "serving hls file---"
    HomeController.serve_hls(conn, %{"file" => file})
  end
	
	get "/socket" do
		conn
		|> validate_csrf_token()
		|> WebSockAdapter.upgrade(WebSocketHandler, [], timeout: 60_000)
		|> halt()
	end
	
	match _ do
		send_resp(conn, 404, "not found")
	end

	defp validate_csrf_token(conn) do
		%{"_csrf_token" => session_token} = 
			conn 
			|> Plug.Conn.fetch_session() 
			|> Plug.Conn.get_session()

		%Plug.Conn{query_params: %{"csrf_token" => params_token}} = 
			Plug.Conn.fetch_query_params(conn)

    if params_token == session_token do
      conn
    else
      Plug.Conn.halt(conn)
    end
  end
end