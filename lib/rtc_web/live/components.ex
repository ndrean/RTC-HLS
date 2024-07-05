defmodule RtcWeb.Spinner do
  use Phoenix.Component
  @moduledoc false
  alias Phoenix.LiveView.JS

  def show_loader(js \\ %JS{}), do: JS.show(js, to: "#spinner")
  def hide_loader(js \\ %JS{}), do: JS.hide(js, to: "#spinner")

  attr :spinner, :boolean, default: true

  def spin(assigns) do
    ~H"""
    <div
      :if={@spinner}
      id="spinner"
      role="status"
      data-plz-wait={show_loader()}
      data-ok-done={hide_loader()}
    >
      <div class="relative w-12 h-12 animate-spin rounded-full bg-gradient-to-r from-purple-400 via-blue-500 to-red-400 ">
        <div class="absolute top-1/2 left-1/2 transform -translate-x-1/2 -translate-y-1/2 w-3 h-3 bg-gray-200 rounded-full border-2 border-white">
        </div>
      </div>
    </div>
    """
  end
end

defmodule RtcWeb.Header do
  use Phoenix.Component

  @moduledoc """
  Header component to display metadata
  """

  attr :user_id, :string
  attr :pid, :string
  attr :room_id, :string
  attr :header, :string
  attr :id, :string

  def display(assigns) do
    ~H"""
    <div>
      <h1 class="text-2xl"><%= @header %></h1>
      <hr />
      <p>Liveview socket id: <%= @id %>, , <%= @pid %></p>
      <p>User id: <%= @user_id %></p>
      <h2>Attending room: <%= @room_id %></h2>
      <p id="stats"></p>
      <hr />
    </div>
    """
  end
end

defmodule RtcWeb.RoomForm do
  @moduledoc """
  Select Form with "room:id" input
  """
  use Phoenix.Component
  alias Phoenix.LiveView.JS

  import RtcWeb.CoreComponents

  attr :form, :map
  attr :min, :integer
  attr :field, :atom
  attr :id, :string
  attr :max, :integer
  attr :title, :string
  attr :options, :list
  attr :errors, :list, default: []
  attr :disabled_rooms, :list, default: []

  def select(assigns) do
    ~H"""
    <.form
      id={@id}
      for={@form}
      phx-submit="goto"
      class="flex flex-wrap items-center justify-between space-x-2 w-full"
    >
      <.button class="text-2xl md:mt-0 flex-shrink-0 mt-2" type="submit"><%= @title %></.button>
      <div class="flex-1">
        <.input
          type="select"
          field={@form[@field]}
          class="flex-grow min-w-1 p-4 text-lg"
          options={@options}
        />
      </div>
    </.form>
    """
  end
end

defmodule RtcWeb.Navigate do
  use Phoenix.Component
  alias Phoenix.LiveView.JS
  use RtcWeb, :verified_routes
  import RtcWeb.CoreComponents, only: [icon: 1]

  attr :t, :string
  attr :id, :string
  attr :link_text, :string
  attr :inner_text, :string
  attr :action, :map

  def display_tab(assigns) do
    ~H"""
    <div>
      <div class="flex justify-center my-4">
        <.link
          replace
          phx-click={@action}
          class="p-4 text-xl md:text-3xl font-bold bg-[bisque] text-[midnightblue] hover:text-blue-700 transition phx-submit-loading:opacity-75 rounded-lg"
        >
          <%= @link_text %>
        </.link>
      </div>
      <div class="flex justify-center mt-8">
        <div class="w-full max-w-lg md:w-1/2 lg:w-1/3 p-4 bg-gray-100 border rounded-md">
          <p class="text-left">
            <%= @inner_text %>
          </p>
        </div>
      </div>
    </div>
    """
  end

  @moduledoc """
  Component to navigate:

  - back home
  - display tabs to select different views: Echo, ExWebRTC and WebRTC
  """

  attr :list, :list
  attr :active_tab, :string

  def tab_selector(assigns) do
    ~H"""
    <nav class="w-full mb-4">
      <ul class="flex flex-col md:flex-row md:space-x-4">
        <li
          :for={%{tab_id: tab_id, live_action: action, title: title} <- @list}
          class={[
            " md:py-0 text-center",
            @active_tab == action && " font-bold text-[midnightblue] rounded bg-[bisque]"
          ]}
        >
          <.link
            phx-click={JS.show(to: tab_id) |> JS.push("switch", value: %{tab: action})}
            class={[
              "block px-2 py-1 md:px-4 md:py-2 rounded-md text-blue-500 border border-blue-500 hover:bg-blue-500 hover:text-white transition text-sm md:text-base",
              @active_tab == action && "bg-[bisque]"
            ]}
          >
            <span class="ml-1"><%= title %></span>
          </.link>
        </li>
      </ul>
    </nav>
    """
  end

  attr :spinner, :boolean, default: true

  def home(assigns) do
    ~H"""
    <div class="flex flex-col items-center space-y-4 mb-4">
      <.link navigate={~p"/"} class="border-solid rounded">
        <.icon name="hero-home" class="h-8 w-8 mr-4" />
        <span class="text-2xl">Back to the Lobby</span>
      </.link>
      <RtcWeb.Spinner.spin spinner={@spinner} />
    </div>
    """
  end

  def reload_home(assigns) do
    ~H"""
    <div class="flex flex-col items-center space-y-4 mb-4">
      <.link href={~p"/"} class="border-solid rounded">
        <.icon name="hero-home" class="h-8 w-8 mr-4" />
        <span class="text-2xl">Back to the Lobby</span>
      </.link>
      <RtcWeb.Spinner.spin spinner={@spinner} />
    </div>
    """
  end
end

defmodule RtcWeb.UsersInRoom do
  @moduledoc """
  Component to list users in a room
  """
  use Phoenix.Component

  attr :room, :string
  attr :room_id, :integer
  attr :streams, :any

  def list(assigns) do
    ~H"""
    <div id="users-in-room" class="mt-4">
      <h2>Users in: <%= @room %></h2>
      <br />

      <table>
        <tbody phx-update="stream" id="room">
          <tr
            :for={{dom_id, %{id: user_id, metas: [%{room_id: room_id}]}} <- @streams.presences}
            id={dom_id}
          >
            <td :if={@room_id == room_id}>
              <%= user_id %>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end
end

defmodule RtcWeb.Videos do
  @moduledoc """
  Display videos
  """
  use Phoenix.Component

  def play(assigns) do
    ~H"""
    <div
      id="ex-videos"
      class="video-container relative w-full max-w-4xl h-3/5 max-h-screen bg-black rounded-lg overflow-y-auto shadow-lg"
    >
      <figure>
        <video id="ex-remote" class="w-full h-full object-cover rounded-lg" />
        <video
          id="ex-local"
          autoplay
          playsinline
          class="absolute top-2 right-2 w-1/4 h-1/4 object-cover border-2 border-white rounded-lg shadow-md cursor-move"
        />
      </figure>
    </div>
    """
  end

  def grid(assigns) do
    ~H"""
    <div class="container mx-auto p-4" id="v-grid">
      <div id="videos" class="grid gap-4 sm:grid-cols-1 md:grid-cols-2">
        <figure>
          <video id="local" class="w-full h-auto object-cover rounded-lg max-h-60" controls autoplay>
          </video>
          <figcaption>Local Video</figcaption>
        </figure>
      </div>
    </div>
    """
  end

  def face(assigns) do
    ~H"""
    <div class="container mx-auto p-4 relative" id="canvas-video">
      <p>The webcam</p>
      <video
        id="webcam"
        width="720"
        height="560"
        class="w-full h-auto object-cover rounded-lg"
        controls
      >
      </video>
      <br />
      <div id="captured"></div>
      <br />
      <p>
        The video element below displayed captures chunks with the face detection. These chunks are uplaoded to the server
      </p>
      <video
        id="overlayed"
        width="720"
        height="560"
        class="w-full h-auto object-cover rounded-lg"
        controls
        autoplay
      >
      </video>
    </div>
    """
  end

  # width="720" height="560"

  def canvas(assigns) do
    ~H"""
    <div class="container mx-auto p-4" id="canvas-video">
      <div id="v-canvas" class="grid gap-4 sm:grid-cols-1 md:grid-cols-2">
        <figure>
          <video
            id="webcam"
            width="640"
            height="480"
            class="w-full h-auto object-cover rounded-lg max-h-60"
            controls
            autoplay
          >
          </video>
          <figcaption>Local Video</figcaption>
        </figure>
        <%!-- <canvas id="overlay"></canvas> --%>
      </div>
    </div>
    """
  end

  def frame(assigns) do
    ~H"""
    <div class="container mx-auto p-4 flex flex-col align-center">
      <figure>
        <video
          id="webcam"
          width="640"
          height="480"
          class="w-full h-auto object-cover rounded-lg max-h-60"
          controls
          autoplay
        >
        </video>
        <figcaption>Local Video</figcaption>
      </figure>
      <figure class="flex flex-col align-center">
        <img id="check-frame" class="w-1/2 h-auto object-cover rounded-lg max-h-60" />
      </figure>
      <figcaption>Captured frame</figcaption>
    </div>
    """
  end
end
