defmodule PoeFlipFinder.Repo.Migrations.AddStartAtToLeague do
  use Ecto.Migration

  # GGG's own Leagues API already returns `startAt` (docs/DATA_SOURCES.md
  # § League List) -- this just persists it so docs/PRD.md § 7.14's
  # "which day of the league are we on" computation has a real timestamp
  # to work from, instead of guessing.
  def change do
    alter table(:league) do
      add :start_at, :utc_datetime
    end
  end
end
