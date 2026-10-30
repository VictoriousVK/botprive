// The ICT explainer: liquidity, sweep, market structure shift, fair value gap, drawn step by step.
// It is a teaching drawing, labelled as such, not an output of the product's Analyst.
import { AbsoluteFill, interpolate, useCurrentFrame, useVideoConfig } from "remotion";
import { Backdrop, Grain } from "../components/Backdrop";
import { ictSequence } from "../data/illustration";
import { C, EASE, F } from "../theme";

const clamp01 = (v: number) => Math.min(1, Math.max(0, v));

export const FvgScene: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const t = frame / fps;
  const seq = ictSequence();
  const X0 = 250;
  const Y0 = 190;
  const W = 1420;
  const H = 640;
  const lo = 95.2;
  const hi = 106;
  const y = (v: number) => Y0 + H - ((v - lo) / (hi - lo)) * H;
  const step = W / (seq.candles.length + 2);
  const cx = (i: number) => X0 + step * (i + 1);
  // When each candle appears.
  const shownAt = (i: number) => (i <= 12 ? 0.3 + i * 0.3 : i === 13 ? 6.4 : i <= 16 ? 9.0 + (i - 14) * 0.45 : 12.6 + (i - 17) * 0.35);
  const push = interpolate(t, [0, 15], [1, 1.07]);
  const liq = EASE.out(clamp01((t - 4.6) / 1.0));
  const liqFlash = interpolate(t, [6.5, 6.7, 7.6], [0, 1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const mss = EASE.out(clamp01((t - 9.6) / 0.9));
  const fvg = EASE.out(clamp01((t - 11.8) / 0.8));
  const label = (at: number) => EASE.out(clamp01((t - at) / 0.6));

  return (
    <AbsoluteFill>
      <Backdrop grid glow={0.6} />
      <div style={{ position: "absolute", left: 90, top: 70, display: "flex", gap: 18, alignItems: "baseline", opacity: label(0.1) }}>
        <span style={{ fontFamily: F.mono, fontSize: 18, letterSpacing: "0.32em", color: C.gold }}>ICT · SMART MONEY CONCEPTS</span>
      </div>
      <div style={{ position: "absolute", right: 90, top: 64, padding: "7px 16px", borderRadius: 999, border: `1px solid ${C.hair}`, fontFamily: F.mono, fontSize: 15, letterSpacing: "0.18em", color: C.gold, opacity: label(0.2) }}>
        ILLUSTRATION PÉDAGOGIQUE
      </div>
      <AbsoluteFill style={{ transform: `scale(${push})`, transformOrigin: "62% 50%" }}>
        <svg width="100%" height="100%">
          {[0.2, 0.4, 0.6, 0.8].map((k) => (
            <line key={k} x1={X0} x2={X0 + W} y1={Y0 + H * k} y2={Y0 + H * k} stroke="rgba(212,179,116,0.07)" />
          ))}
          {/* buy-side liquidity: equal highs */}
          <line x1={cx(3)} x2={cx(3) + (cx(seq.candles.length - 1) - cx(3)) * liq} y1={y(seq.highs)} y2={y(seq.highs)} stroke={C.goldLight} strokeWidth={2} strokeDasharray="10 9" strokeOpacity={0.85} />
          {[4, 8, 12].map((i) => (
            <circle key={i} cx={cx(i)} cy={y(seq.highs)} r={7 + liqFlash * 8} fill="none" stroke={C.goldLight} strokeOpacity={liq * (0.6 + liqFlash * 0.4)} strokeWidth={1.6} />
          ))}
          {/* swing low broken by the displacement */}
          <line x1={cx(7)} x2={cx(7) + (cx(18) - cx(7)) * mss} y1={y(seq.swingLow)} y2={y(seq.swingLow)} stroke={C.grey} strokeWidth={1.6} strokeDasharray="4 7" />
          {/* fair value gap */}
          <rect x={cx(seq.fvg.first) - step * 0.4} y={y(seq.fvg.top)} width={(cx(seq.candles.length - 1) - cx(seq.fvg.first) + step * 0.8) * fvg} height={y(seq.fvg.bottom) - y(seq.fvg.top)} fill="rgba(212,179,116,0.16)" stroke={C.gold} strokeOpacity={0.7 * fvg} strokeWidth={1.4} />
          {/* the three candles that leave the gap */}
          {fvg > 0 && <path d={`M${cx(14) - step * 0.4} ${y(97.2)} v10 H${cx(16) + step * 0.4} v-10`} fill="none" stroke={C.goldLight} strokeOpacity={fvg} strokeWidth={1.6} />}
          {/* candles */}
          {seq.candles.map((c, i) => {
            const p = EASE.out(clamp01((t - shownAt(i)) / 0.35));
            if (p <= 0) return null;
            const up = c.c >= c.o;
            const col = up ? C.gold : "#8A8F98";
            const x = cx(i);
            const body = Math.max(3, Math.abs(y(c.o) - y(c.c)));
            const isSweep = i === seq.sweep;
            return (
              <g key={i} opacity={p} transform={`translate(0, ${(1 - p) * 14})`}>
                <line x1={x} x2={x} y1={y(c.h)} y2={y(c.l)} stroke={isSweep ? C.goldLight : col} strokeWidth={isSweep ? 2.4 : 1.8} />
                <rect x={x - step * 0.3} width={step * 0.6} y={y(Math.max(c.o, c.c))} height={body} fill={up ? col : "#2A2D33"} stroke={col} strokeWidth={1.4} rx={1.5} />
              </g>
            );
          })}
        </svg>
        {/* labels */}
        <Label x={cx(5)} y={y(seq.highs) - 72} o={label(4.8)} kicker="BUY-SIDE LIQUIDITY" text="Sommets égaux : la liquidité" />
        <Label x={cx(13) + 18} y={y(105.3) - 36} o={label(6.6)} kicker="SWEEP" text="Prise de liquidité" />
        <Label x={cx(17) + 30} y={y(seq.swingLow) + 16} o={label(9.8)} kicker="MSS" text="Cassure de structure" />
        <Label x={cx(19) + 20} y={y(seq.fvg.top) - 80} o={label(12.0)} kicker="FAIR VALUE GAP" text="Déséquilibre sur trois bougies" gold />
      </AbsoluteFill>
      <Grain />
    </AbsoluteFill>
  );
};

const Label: React.FC<{ x: number; y: number; o: number; kicker: string; text: string; gold?: boolean }> = ({ x, y, o, kicker, text, gold }) => (
  <div style={{ position: "absolute", left: x, top: y, opacity: o, transform: `translateY(${(1 - o) * 10}px)`, padding: "10px 16px", borderRadius: 12, background: "rgba(5,5,6,0.8)", border: `1px solid ${gold ? C.gold : C.hair}` }}>
    <div style={{ fontFamily: F.mono, fontSize: 15, letterSpacing: "0.26em", color: C.gold }}>{kicker}</div>
    <div style={{ marginTop: 6, fontFamily: F.display, fontWeight: 600, fontSize: 24, color: C.white, whiteSpace: "nowrap" }}>{text}</div>
  </div>
);
