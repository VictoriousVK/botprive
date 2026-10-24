/** Motif décoratif de chandeliers (repris des affiches). */
const SERIES = [
  [62, 40, 70, 30], [44, 58, 66, 36], [56, 34, 60, 26], [38, 50, 56, 30], [48, 30, 52, 22],
  [32, 46, 50, 26], [42, 24, 46, 16], [28, 40, 46, 20], [36, 18, 40, 10], [22, 34, 38, 14],
  [30, 14, 34, 8], [18, 28, 32, 10], [24, 8, 28, 4], [12, 22, 26, 6],
] as const; // [ouverture, clôture, bas, haut] en unités inversées (0 = haut)

export function Candles({ color = "#9d5cf5", className }: { color?: string; className?: string }) {
  const w = 34;
  return (
    <svg className={className} viewBox={`0 0 ${SERIES.length * w} 80`} aria-hidden="true" focusable="false">
      {SERIES.map(([open, close, low, high], i) => {
        const x = i * w + w / 2;
        const bullish = close < open;
        const top = Math.min(open, close);
        const height = Math.max(Math.abs(open - close), 2);
        return (
          <g key={i}>
            <line x1={x} x2={x} y1={high} y2={low} stroke={color} strokeWidth={1.5} />
            <rect
              x={x - 8}
              y={top}
              width={16}
              height={height}
              fill={bullish ? color : "transparent"}
              stroke={color}
              strokeWidth={1.5}
            />
          </g>
        );
      })}
    </svg>
  );
}
