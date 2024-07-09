defmodule MixMediasource.MixProject do
  use Mix.Project

  def project do
    [
      app: :mix_mediasource,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {App, []},
      extra_applications: [:logger, :observer, :wx, :runtime_tools]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:plug, "~> 1.6"},
      {:plug_crypto, "~> 1.2"},
      {:bandit, "~> 1.5"},
      {:websock_adapter, "~> 0.5"},
      {:ex_cmd, "~> 0.12"},
      {:evision, "~> 0.2"}
    ]
  end
end
