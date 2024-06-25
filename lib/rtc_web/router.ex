defmodule RtcWeb.Router do
  use RtcWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {RtcWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug Plug.Parsers, parsers: [:urlencoded, :multipart]
    plug :put_user_token
  end

  pipeline :files do
    plug :put_secure_browser_headers
    plug Plug.Parsers, parsers: [:urlencoded, :multipart]
  end

  scope "/", RtcWeb do
    pipe_through :browser

    live_session :default do
      live "/", RoomLive, :lobby
      live "/echo/:echo", RoomLive, :echo
      live "/ex/:ex_room_id", RoomLive, :room
      live "/evision/:evision_room_id", RoomLive, :evision
      live "/web/:web_room_id", RoomLive, :web
      live "/frame", RoomLive, :frame
      live "/face", RoomLive, :face
      live "/hls_stream", RoomLive, :hls
      live "/live_stream", RoomLive, :live
    end
  end

  scope "/api", RtcWeb do
    pipe_through :files
    post "/live-upload", HlsController, :files
  end

  scope "/hls", RtcWeb do
    pipe_through :browser
    get ":file", HlsController, :segment
  end

  # Other scopes may use custom stacks.
  # scope "/api", RtcWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:rtc, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: RtcWeb.Telemetry
    end
  end

  def put_user_token(conn, _) do
    conn =
      Plug.Conn.fetch_session(conn)

    Plug.CSRFProtection.delete_csrf_token()
    Plug.CSRFProtection.get_csrf_token()

    case Plug.Conn.get_session(conn, :user_id) |> dbg() do
      nil ->
        uid = System.unique_integer() |> abs() |> Integer.to_string()
        user_id = Phoenix.Token.sign(RtcWeb.Endpoint, "user id", uid)

        user_token =
          Phoenix.Token.sign(RtcWeb.Endpoint, "user token", uid)

        conn
        |> Plug.Conn.put_session(:user_id, user_id)
        |> Plug.Conn.put_session(:user_token, user_token)
        |> Plug.Conn.assign(:user_token, user_token)

      user_id ->
        user_token =
          Phoenix.Token.sign(RtcWeb.Endpoint, "user token", user_id)

        Plug.Conn.assign(conn, :user_token, user_token)
    end
  end
end
