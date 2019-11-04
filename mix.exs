defmodule Mroxy.MixProject do
  use Mix.Project

  def project do
    [
      app: :mroxy,
      version: "0.1.0",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: [main: "Mroxy", extras: ["README.md"]],
      releases: releases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Mroxy.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
    ]
  end

  defp description() do
    "MS SQL Proxy Service enabling scalable remote debug protocol connections."
  end

  defp package() do
    [
      name: "mroxy",
      files: ["config", "lib", "mix.exs", "README*"],
      maintainers: ["Dan Todor (@dantodor)"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/dantodor/mroxy"}
    ]
  end

  defp releases() do
    [
      demo: [
        include_executables_for: [:unix],
        applications: [runtimetools: :permanent],
      ]
    ]
  end
end
