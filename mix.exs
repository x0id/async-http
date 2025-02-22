defmodule AsyncHttp.MixProject do
  use Mix.Project

  def project do
    [
      app: :async_http,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {AsyncHttp.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:mint, "~> 1.0"},
      {:split_states, github: "x0id/split-states", tag: "0.2.1"},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false}
    ]
  end
end
