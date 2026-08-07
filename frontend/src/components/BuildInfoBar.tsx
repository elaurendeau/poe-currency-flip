import { formatAbsoluteTimestamp } from '../presenters/timestampPresenter';

// docs/PRD.md § 7.11: answers "is this actually the new code?" directly from
// the page itself, instead of guessing from Render/Vercel's async post-deploy
// rebuild timing. __GIT_HASH__/__BUILD_DATE__ are compile-time constants
// injected by vite.config.ts -- no runtime API call, no backend involvement.
export function BuildInfoBar() {
  return (
    <footer className="app-footer">
      Build <span className="build-hash">{__GIT_HASH__}</span> · {formatAbsoluteTimestamp(__BUILD_DATE__)}
    </footer>
  );
}
