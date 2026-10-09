// Illustrative market shapes for the motion graphics (intro, explainer). These are drawings, not
// data: the films label them « Illustration », and never present them as the product's output
// or as trading results.
import { random } from "remotion";

export type Candle = { o: number; h: number; l: number; c: number };

/** A random-walk candle series, deterministic for a given seed. */
export function walk(n: number, seed: string, drift = 0, vol = 1): Candle[] {
  let p = 100;
  return Array.from({ length: n }, (_, i) => {
    const r = (k: string) => random(`${seed}-${i}-${k}`);
    const o = p;
    const c = o + (r("d") - 0.5 + drift) * 2 * vol;
    const h = Math.max(o, c) + r("h") * 0.9 * vol;
    const l = Math.min(o, c) - r("l") * 0.9 * vol;
    p = c;
    return { o, h, l, c };
  });
}

/**
 * The textbook sequence the explainer draws: a range with equal highs (buy-side liquidity), a sweep
 * above them, a bearish displacement that breaks the last swing low (market structure shift) and
 * leaves a fair value gap, then a retracement into the gap.
 */
export function ictSequence(): { candles: Candle[]; highs: number; swingLow: number; sweep: number; fvg: { top: number; bottom: number; first: number } } {
  const C = (o: number, h: number, l: number, c: number): Candle => ({ o, h, l, c });
  const candles: Candle[] = [
    C(100, 101.2, 99.4, 100.8), C(100.8, 102.1, 100.3, 101.7), C(101.7, 103.0, 101.2, 102.6), C(102.6, 103.4, 101.6, 101.9),
    C(101.9, 104.0, 101.5, 103.7), C(103.7, 104.0, 102.4, 102.7), C(102.7, 103.1, 101.3, 101.6), C(101.6, 102.4, 100.9, 102.2),
    C(102.2, 104.0, 101.9, 103.6), C(103.6, 103.8, 102.2, 102.5), C(102.5, 102.9, 101.0, 101.4), C(101.4, 102.8, 101.1, 102.5),
    C(102.5, 104.0, 102.2, 103.5), C(103.5, 105.3, 102.9, 103.1), C(103.1, 103.4, 101.6, 101.9), C(101.9, 102.0, 98.8, 99.2),
    C(99.2, 99.9, 97.9, 98.3), C(98.3, 99.6, 97.8, 99.4), C(99.4, 100.7, 99.0, 100.5), C(100.5, 101.1, 99.6, 99.9),
    C(99.9, 100.2, 98.0, 98.4), C(98.4, 98.8, 96.6, 96.9), C(96.9, 97.6, 95.8, 96.2),
  ];
  // Bearish gap between candle 14's low (101.6) and candle 16's high (99.9).
  return { candles, highs: 104.0, swingLow: 100.9, sweep: 13, fvg: { top: 101.6, bottom: 99.9, first: 14 } };
}
