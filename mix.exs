defmodule Apitizer.MixProject do
  use Mix.Project

  def project do
    [
      app: :apitizer,
      version: "0.1.0",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Docs
      name: "Apitizer",
      source_url: "https://git.sr.ht/~drtheuns/apitizer",
      docs: [
        extra: ["README.md"]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:plug, "~> 1.8"},
      {:ecto, "~> 3.0"},
      {:nimble_parsec, "~> 0.5"},
      {:ex_doc, "~> 0.21", only: :dev, runtime: false}
    ]
  end
end
