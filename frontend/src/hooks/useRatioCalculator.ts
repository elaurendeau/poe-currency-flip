import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  closestRatioMatches,
  formatAchievedRatio,
  isExactRatioMatch,
  nearbyWholeRatioSuggestions,
  nearestLeftForRight,
  nearestRightForLeft,
  ratioValue,
  simplestIntegerRatio,
  type ClosestMatch,
  type RatioAnchor,
  type RatioSuggestion,
} from '../presenters/ratioCalculatorPresenter';

export interface RatioCalculator {
  isOpen: boolean;
  toggleOpen: () => void;
  close: () => void;
  ratioText: string;
  setRatioText: (value: string) => void;
  leftText: string;
  setLeftText: (value: string) => void;
  rightText: string;
  setRightText: (value: string) => void;
  isRatioValid: boolean;
  achievedRatio: string | null;
  isExactMatch: boolean;
  closestMatches: ClosestMatch[];
  suggestions: RatioSuggestion[];
}

export function useRatioCalculator(): RatioCalculator {
  const [isOpen, setIsOpen] = useState(false);
  const [ratioText, setRatioTextState] = useState('');
  const [leftText, setLeftTextState] = useState('');
  const [rightText, setRightTextState] = useState('');
  const [anchor, setAnchor] = useState<RatioAnchor>('left');

  const toggleOpen = useCallback(() => setIsOpen((open) => !open), []);
  const close = useCallback(() => setIsOpen(false), []);

  const ratio = useMemo(() => ratioValue(ratioText), [ratioText]);
  const simplest = useMemo(() => simplestIntegerRatio(ratioText), [ratioText]);

  // Re-derive the smallest whole-number pair whenever the ratio itself
  // changes to a new valid value -- edits to left/right alone don't touch
  // ratioText, so they don't retrigger this.
  useEffect(() => {
    if (!simplest) return;
    setLeftTextState(String(simplest.left));
    setRightTextState(String(simplest.right));
  }, [simplest]);

  const setRatioText = useCallback((value: string) => {
    setRatioTextState(value);
    setAnchor('left');
  }, []);

  const setLeftText = useCallback(
    (value: string) => {
      setLeftTextState(value);
      setAnchor('left');
      const num = Number(value);
      if (ratio !== null && value.trim() !== '' && Number.isFinite(num)) {
        setRightTextState(String(nearestRightForLeft(num, ratio)));
      }
    },
    [ratio],
  );

  const setRightText = useCallback(
    (value: string) => {
      setRightTextState(value);
      setAnchor('right');
      const num = Number(value);
      if (ratio !== null && value.trim() !== '' && Number.isFinite(num)) {
        setLeftTextState(String(nearestLeftForRight(num, ratio)));
      }
    },
    [ratio],
  );

  const leftNum = Number(leftText);
  const rightNum = Number(rightText);
  const achievedRatio = ratio !== null ? formatAchievedRatio(leftNum, rightNum) : null;
  const isExactMatch = ratio !== null && isExactRatioMatch(leftNum, rightNum, ratio);

  const anchorValue = anchor === 'left' ? leftNum : rightNum;

  const closestMatches = useMemo(() => {
    if (ratio === null || isExactMatch || !Number.isFinite(anchorValue)) return [];
    return closestRatioMatches(ratio, anchor, anchorValue);
  }, [ratio, isExactMatch, anchor, anchorValue]);

  const suggestions = useMemo(() => {
    if (ratio === null || isExactMatch || !Number.isFinite(anchorValue)) return [];
    return nearbyWholeRatioSuggestions(ratio, anchor, anchorValue);
  }, [ratio, isExactMatch, anchor, anchorValue]);

  return {
    isOpen,
    toggleOpen,
    close,
    ratioText,
    setRatioText,
    leftText,
    setLeftText,
    rightText,
    setRightText,
    isRatioValid: ratio !== null,
    achievedRatio,
    isExactMatch,
    closestMatches,
    suggestions,
  };
}
