import { act, renderHook } from '@testing-library/react';
import type { MouseEvent as ReactMouseEvent } from 'react';
import { describe, expect, it, vi } from 'vitest';
import { useRowContextMenu } from './useRowContextMenu';

function fakeMouseEvent(clientX: number, clientY: number): ReactMouseEvent {
  return { preventDefault: vi.fn(), clientX, clientY } as unknown as ReactMouseEvent;
}

describe('useRowContextMenu', () => {
  it('starts closed', () => {
    const { result } = renderHook(() => useRowContextMenu<string>());

    expect(result.current.menu).toBeNull();
  });

  it('opens at the event position with the given payload, preventing the native menu', () => {
    const { result } = renderHook(() => useRowContextMenu<string>());
    const event = fakeMouseEvent(10, 20);

    act(() => result.current.openMenu(event, 'payload-a'));

    expect(result.current.menu).toEqual({ x: 10, y: 20, payload: 'payload-a' });
    expect(event.preventDefault).toHaveBeenCalled();
  });

  it('closes explicitly via closeMenu', () => {
    const { result } = renderHook(() => useRowContextMenu<string>());

    act(() => result.current.openMenu(fakeMouseEvent(0, 0), 'p'));
    act(() => result.current.closeMenu());

    expect(result.current.menu).toBeNull();
  });

  it('closes when a click occurs anywhere in the document', () => {
    const { result } = renderHook(() => useRowContextMenu<string>());

    act(() => result.current.openMenu(fakeMouseEvent(0, 0), 'p'));
    expect(result.current.menu).not.toBeNull();

    act(() => {
      document.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    });

    expect(result.current.menu).toBeNull();
  });
});
