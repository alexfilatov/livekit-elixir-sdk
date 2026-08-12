defmodule Livekit.MixProject do
  use Mix.Project

  def project do
    [
      app: :livekit,
      version: "0.1.4",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "Livekit",
      source_url: "https://github.com/alexfilatov/livekit",
      # Docs
      docs: [
        main: "Livekit",
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
      compilers: Mix.compilers() ++ [:proto],
      # Dialyzer configuration
      dialyzer: [
        ignore_warnings: "dialyzer.ignore-warnings",
        plt_add_apps: [:mix]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      # :inets and :ssl are what OTP's httpc needs — the default adapter.
      extra_applications: [:logger, :crypto, :inets, :ssl, :gun, :grpc]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:protobuf, "~> 0.14.0"},
      {:tesla, "~> 1.7"},
      # No HTTP client dependency by design — the Tesla adapter is chosen by
      # the consumer via `config :livekit, :tesla_adapter` and defaults to
      # OTP's httpc, which needs nothing. See `Livekit.HTTP`. Finch is here
      # only so the recommended production adapter can be compiled and
      # tested; it is optional and not started by this library.
      {:finch, "~> 0.19", optional: true},
      {:jason, "~> 1.4"},
      {:joken, "~> 2.6"},
      {:inflex, "~> 2.1"},
      {:grpc, "~> 0.10.2"},
      # Development dependencies
      {:ex_doc, "~> 0.29", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      # Test dependencies
      {:bypass, "~> 2.1", only: :test},
      {:mock, "~> 0.3.0", only: :test},
      # NIF dependencies (optional — only needed when compiling the Rust WebRTC client)
      {:rustler, "~> 0.37", runtime: false, optional: true}
    ]
  end

  defp description do
    """
    Livekit server SDK for Elixir - enables you to build real-time video/audio applications with Livekit.
    """
  end

  defp package do
    [
      name: "livekit",
      files: ~w(lib native priv mix.exs README.md LICENSE),
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/alexfilatov/livekit"
      }
    ]
  end
end
