defmodule PoeFlipFinderWeb.BuildInfo do
  @moduledoc """
  docs/PRD.md § 7.11: answers "is this actually the new code?" directly
  from the page itself, instead of guessing from Render's async
  post-deploy rebuild timing. Computed once at compile time (module
  attributes), matching the Vite version's __GIT_HASH__/__BUILD_DATE__
  compile-time constants -- no runtime API call, no extra request.
  """

  # `.git` isn't reachable inside the production Docker build at all -- the
  # build context is `app/` (this directory), and `.git` lives one level up
  # at the repo root, outside any Docker build context by design (confirmed
  # by reproducing the exact "file not found in build context" failure
  # locally). Render sets RENDER_GIT_COMMIT for every deploy and -- for
  # Docker-based services specifically -- auto-forwards it as a build ARG
  # too (see docs/DEPLOYMENT.md), so the Dockerfile declares that ARG and
  # this reads it as a plain env var, staying a true compile-time constant
  # in production without ever needing `.git` in the image. Local dev
  # (`mix phx.server`, no RENDER_GIT_COMMIT) falls back to reading
  # `.git/HEAD` directly from the repo root one level up.
  @git_hash (case System.get_env("RENDER_GIT_COMMIT") do
               # An unset build ARG interpolated into ENV becomes an empty
               # string, not an absent variable -- System.get_env sees ""
               # (confirmed by reproducing the exact empty-footer symptom
               # from a local `docker build` with no --build-arg passed),
               # so "" must fall back too, not be treated as a real value.
               sha when is_binary(sha) and sha != "" ->
                 String.slice(sha, 0, 7)

               _ ->
                 case File.read("../.git/HEAD") do
                   {:ok, "ref: " <> ref} ->
                     case ref |> String.trim() |> then(&File.read(Path.join("../.git", &1))) do
                       {:ok, sha} -> String.slice(String.trim(sha), 0, 7)
                       _ -> "unknown"
                     end

                   {:ok, sha} ->
                     String.slice(String.trim(sha), 0, 7)

                   _ ->
                     "unknown"
                 end
             end)

  @build_date DateTime.utc_now()

  @spec git_hash() :: String.t()
  def git_hash, do: @git_hash

  @spec build_date() :: DateTime.t()
  def build_date, do: @build_date
end
