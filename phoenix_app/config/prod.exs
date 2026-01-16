import Config

# Database configuration will come from runtime.exs

# Endpoint configuration for production
config :webtoon_web, WebtoonWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json"

# Don't log debug messages in production
config :logger, level: :info

# Runtime production configuration is in runtime.exs
