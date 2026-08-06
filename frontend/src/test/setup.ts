import '@testing-library/jest-dom/vitest';
import { cleanup } from '@testing-library/react';
import { afterEach } from 'vitest';

// Without test.globals in vite.config.ts, React Testing Library can't
// auto-detect a global afterEach to register its own cleanup, so each
// rendered component would otherwise leak into the next test in the file.
afterEach(() => {
  cleanup();
});
