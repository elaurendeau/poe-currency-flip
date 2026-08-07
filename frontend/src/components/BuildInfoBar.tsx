import { formatAbsoluteTimestamp } from '../presenters/timestampPresenter';

// docs/PRD.md § 7.11: answers "is this actually the new code?" directly from
// the page itself, instead of guessing from Render/Vercel's async post-deploy
// rebuild timing. __GIT_HASH__/__BUILD_DATE__ are compile-time constants
// injected by vite.config.ts -- no runtime API call, no backend involvement.
export function BuildInfoBar() {
  // Spaces around the hash/separator are explicit expression children
  // ({' '}), not literal JSX text -- JSX trims trailing whitespace at the
  // end of a text line (e.g. "Build " right before a tag on the same
  // line), which silently swallows a plain string literal space here.
  return (
    <footer className="app-footer">
      Build{' '}
      <span className="build-hash">{__GIT_HASH__}</span>
      {' · '}
      {formatAbsoluteTimestamp(__BUILD_DATE__)}
    </footer>
  );
}
