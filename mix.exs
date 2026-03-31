defmodule Kodon.MixProject do
  use Mix.Project

  def project do
    [
      app: :kodon,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :xmerl, :eex]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:earmark, "~> 1.4"},
      {:jason, "~> 1.4"},
      {:nimble_publisher, "~> 1.1.1"},
      {:phoenix_live_view, "~> 1.1.28"},
      {:yaml_elixir, "~> 2.12.1"}
    ]
  end
end
