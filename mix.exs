defmodule LiveKit.MixProject do
  use Mix.Project

  def project do
    [
      app: :livekit,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "LiveKit",
      source_url: "https://github.com/gymbile/livekit",
      # Docs
      docs: [
        main: "LiveKit",
        extras: ["README.md"]
      ],
      # Test coverage
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      compilers: Mix.compilers() ++ [:proto]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:protobuf, "~> 0.12.0"},
      {:google_protos, "~> 0.3.0"},
      {:tesla, "~> 1.7"},
      {:hackney, "~> 1.18"},
      {:jason, "~> 1.4"},
      {:joken, "~> 2.6"},
      {:inflex, "~> 2.1"},
      {:twirp, "~> 0.8"},
      # Development dependencies
      {:ex_doc, "~> 0.29", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      # Test dependencies
      {:bypass, "~> 2.1", only: :test},
      {:mock, "~> 0.3.0", only: :test}
    ]
  end

  defp description do
    """
    LiveKit server SDK for Elixir - enables you to build real-time video/audio applications with LiveKit.
    """
  end

  defp package do
    [
      name: "livekit",
      files: ~w(lib priv mix.exs README.md LICENSE),
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/gymbile/livekit"
      }
    ]
  end
end
