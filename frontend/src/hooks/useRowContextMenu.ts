import { useCallback, useEffect, useState } from 'react';
import type { MouseEvent as ReactMouseEvent } from 'react';

export interface ContextMenuState<T> {
  x: number;
  y: number;
  payload: T;
}

export interface RowContextMenu<T> {
  menu: ContextMenuState<T> | null;
  openMenu: (event: ReactMouseEvent, payload: T) => void;
  closeMenu: () => void;
}

// Generic right-click menu positioning/visibility only -- no business logic.
// What the menu item actually does (e.g. toggling a favorite) is the
// caller's concern.
export function useRowContextMenu<T>(): RowContextMenu<T> {
  const [menu, setMenu] = useState<ContextMenuState<T> | null>(null);

  const openMenu = useCallback((event: ReactMouseEvent, payload: T) => {
    event.preventDefault();
    setMenu({ x: event.clientX, y: event.clientY, payload });
  }, []);

  const closeMenu = useCallback(() => setMenu(null), []);

  useEffect(() => {
    if (!menu) return;
    document.addEventListener('click', closeMenu);
    return () => document.removeEventListener('click', closeMenu);
  }, [menu, closeMenu]);

  return { menu, openMenu, closeMenu };
}
