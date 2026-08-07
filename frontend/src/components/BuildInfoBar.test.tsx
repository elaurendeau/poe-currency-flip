import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { BuildInfoBar } from './BuildInfoBar';

describe('BuildInfoBar', () => {
  it('renders the build-time git hash and formatted build date', () => {
    // __GIT_HASH__/__BUILD_DATE__ are real compile-time constants here too --
    // vite.config.ts injects them for the test runner the same as a real
    // build, so this exercises the actual values rather than mocks.
    render(<BuildInfoBar />);

    // Exact match isolates the hash's own <span> from the surrounding
    // footer text; the date is a bare text node, so only the footer's full
    // text contains it -- neither query matches more than one element.
    expect(screen.getByText(__GIT_HASH__)).toBeInTheDocument();
    expect(screen.getByText(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}/)).toBeInTheDocument();
  });
});
