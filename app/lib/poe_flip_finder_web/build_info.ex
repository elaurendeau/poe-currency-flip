defmodule PoeFlipFinderWeb.BuildInfo do
  @moduledoc """
  docs/PRD.md § 7.11: answers "is this actually the new code?" directly
  from the page itself, instead of guessing from Render's async
  post-deploy rebuild timing. Computed once at compile time (module
  attributes), matching the Vite version's __GIT_HASH__/__BUILD_DATE__
  compile-time constants -- no runtime API call, no extra request.
  """

  @git_hash (case System.cmd("git", ["rev-parse", "--short", "HEAD"], stderr_to_stdout: true) do
               {hash, 0} -> String.trim(hash)
               _ -> "unknown"
             end)

  @build_date DateTime.utc_now()

  @spec git_hash() :: String.t()
  def git_hash, do: @git_hash

  @spec build_date() :: DateTime.t()
  def build_date, do: @build_date
end
