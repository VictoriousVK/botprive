// The intro's fly-through: chart fragments at different depths, coming towards the camera.
import { useMemo } from "react";
import { AbsoluteFill, random, useVideoConfig } from "remotion";
import { walk, type Candle } from "../data/illustration";
import { C, F } from "../theme";

type Pane = { x: number; y: number; z: number; w: number; h: number; seed: string; label: string; fvg: boolean; liq: boolean; tilt: number };

const LABELS = ["XAUUSD · M5", "NAS100 · M1", "NY AM · 09:30", "LONDON · 03:00", "US30 · M15", "MNQ · M5", "EURUSD · H1", "XAUUSD · H1", "NQ · M5"];

const ChartPane: React.FC<{ pane: Pane; candles: Candle[] }> = ({ pane, candles }) => {
  const lo = Math.min(...candles.map((c) => c.l));
  const hi = Math.max(...candles.map((c) => c.h));
  const y = (v: number) => pane.h - 24 - ((v - lo) / (hi - lo || 1)) * (pane.h - 48);
  const step = pane.w / candles.length;
  const line = candles.map((c, i) => `${i * step + step / 2},${y(c.c)}`).join(" ");
  const g = Math.floor(candles.length * 0.62);
  return (
    <svg width={pane.w} height={pane.h} viewBox={`0 0 ${pane.w} ${pane.h}`} style={{ overflow: "visible" }}>
      {[0.25, 0.5, 0.75].map((k) => (
        <line key={k} x1={0} x2={pane.w} y1={pane.h * k} y2={pane.h * k} stroke="rgba(212,179,116,0.08)" strokeWidth={1} />
      ))}
      {pane.fvg && <rect x={g * step} y={y(candles[g].h) - 18} width={pane.w - g * step} height={26} fill="rgba(212,179,116,0.12)" stroke="rgba(212,179,116,0.35)" strokeWidth={1} />}
      {pane.liq && <line x1={0} x2={pane.w} y1={y(hi) + 2} y2={y(hi) + 2} stroke={C.gold} strokeOpacity={0.55} strokeDasharray="8 8" strokeWidth={1.4} />}
      {candles.map((c, i) => {
        const up = c.c >= c.o;
        const x = i * step + step / 2;
        const col = up ? C.gold : "#5A5F68";
        return (
          <g key={i}>
            <line x1={x} x2={x} y1={y(c.h)} y2={y(c.l)} stroke={col} strokeWidth={1.4} />
            <rect x={x - step * 0.3} width={step * 0.6} y={y(Math.max(c.o, c.c))} height={Math.max(2, Math.abs(y(c.o) - y(c.c)))} fill={up ? col : "transparent"} stroke={col} strokeWidth={1.2} />
          </g>
        );
      })}
      <polyline points={line} fill="none" stroke={C.goldLight} strokeOpacity={0.45} strokeWidth={2} style={{ filter: "drop-shadow(0 0 6px rgba(234,214,166,0.6))" }} />
      <text x={6} y={18} fill={C.gold} fillOpacity={0.8} fontFamily={F.mono} fontSize={15} letterSpacing="0.18em">
        {pane.label}
      </text>
    </svg>
  );
};

/** progress: 0 → 1 over the fly-through; the panes come from far away and pass the camera. */
export const CandleField: React.FC<{ progress: number; count?: number; opacity?: number }> = ({ progress, count = 9, opacity = 1 }) => {
  const { width, height } = useVideoConfig();
  const portrait = height > width;
  const panes = useMemo<Pane[]>(
    () =>
      Array.from({ length: count }, (_, i) => {
        const r = (k: string) => random(`pane-${i}-${k}`);
        return {
          x: (r("x") - 0.5) * (portrait ? 900 : 1700),
          y: (r("y") - 0.5) * (portrait ? 1500 : 760),
          z: -600 - i * 520,
          w: 760 + r("w") * 520,
          h: 240 + r("h") * 160,
          seed: `c${i}`,
          label: LABELS[i % LABELS.length],
          fvg: r("f") > 0.5,
          liq: r("l") > 0.55,
          tilt: (r("t") - 0.5) * 14,
        };
      }),
    [count, portrait],
  );
  const series = useMemo(() => panes.map((p) => walk(46, p.seed, 0.02, 1)), [panes]);
  const camZ = progress * (count * 520 + 300);
  return (
    <AbsoluteFill style={{ perspective: 1100, perspectiveOrigin: "50% 50%", opacity }}>
      <AbsoluteFill style={{ transformStyle: "preserve-3d" }}>
        {panes.map((p, i) => {
          const z = p.z + camZ;
          const fadeIn = Math.min(1, Math.max(0, (z + 4600) / 1600));
          const fadeOut = Math.min(1, Math.max(0, (260 - z) / 520));
          const o = fadeIn * fadeOut;
          if (o <= 0.01) return null;
          return (
            <div
              key={i}
              style={{
                position: "absolute",
                left: width / 2 + p.x - p.w / 2,
                top: height / 2 + p.y - p.h / 2,
                width: p.w,
                height: p.h,
                opacity: o * 0.9,
                transform: `translateZ(${z}px) rotateY(${p.tilt}deg)`,
                background: "linear-gradient(180deg, rgba(20,22,28,0.55), rgba(8,9,12,0.25))",
                border: "1px solid rgba(212,179,116,0.16)",
                borderRadius: 10,
              }}
            >
              <ChartPane pane={p} candles={series[i]} />
            </div>
          );
        })}
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
