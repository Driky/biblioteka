defmodule WebtoonShared.Repo do
  use Ecto.Repo,
    otp_app: :webtoon_shared,
    adapter: Ecto.Adapters.Postgres
end
