defmodule WebtoonScraper.Scheduler do
  @moduledoc """
  Quantum scheduler for periodic scraping jobs.
  Jobs are staggered to avoid load peaks and reduce ban risk.
  """

  use Quantum, otp_app: :webtoon_scraper
end
