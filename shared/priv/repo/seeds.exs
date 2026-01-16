# Script for populating the database with initial data.
#
# Run with: mix run priv/repo/seeds.exs

alias WebtoonShared.Repo
alias WebtoonShared.Schema.{Webtoon, WebtoonSource}

# Example: Create a webtoon and link it to a source
# Uncomment and modify when you have actual sources to add

{:ok, webtoon} =
  Repo.insert(%Webtoon{
    title: "Solo Leveling",
    slug: "solo-leveling"
  })

Repo.insert(%WebtoonSource{
  webtoon_id: webtoon.id,
  site_id: "mangahub",
  source_url: "https://mangahub.io/manga/solo-leveling_105",
  enabled: true
})

IO.puts("Seeds completed successfully!")
