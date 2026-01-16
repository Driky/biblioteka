import Config

config :webtoon_shared,
  ecto_repos: [WebtoonShared.Repo]

config :webtoon_shared, WebtoonShared.Repo,
  migration_primary_key: [type: :binary_id],
  migration_foreign_key: [type: :binary_id]

# Import environment specific config
import_config "#{config_env()}.exs"
