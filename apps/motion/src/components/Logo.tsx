// The emblem and the ALPHA EDGE wordmark, revealed with a gold light.
import { Img, interpolate, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { BRAND } from "../content/brand";
import { C, EASE, F, goldGradient } from "../theme";

const GOLD_FILTER = "grayscale(1) sepia(1) saturate(2.4) hue-rotate(-10deg) brightness(1.08) contrast(1.05)";

export const Emblem: React.FC<{ size: number; start: number; glow?: number }> = ({ size, start, glow = 1 }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const t = frame / fps - start;
  const p = interpolate(t, [0, 0.9], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: EASE.out });
  const shine = interpolate(t, [0.2, 1.6], [-0.4, 1.4], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: EASE.cine });
  return (
    <div style={{ position: "relative", width: size, height: size, opacity: p, transform: `scale(${0.82 + 0.18 * p})` }}>
      <div style={{ position: "absolute", inset: -size * 0.35, background: `radial-gradient(circle, rgba(234,214,166,${0.28 * glow * p}), transparent 62%)` }} />
      <Img src={staticFile("brand/emblem.svg")} style={{ width: size, height: size, filter: BRAND.logoTint === "gold" ? GOLD_FILTER : undefined }} />
      <div
        style={{
          position: "absolute",
          inset: 0,
          borderRadius: "50%",
          background: `linear-gradient(115deg, transparent ${shine * 100 - 18}%, rgba(255,250,235,0.55) ${shine * 100}%, transparent ${shine * 100 + 18}%)`,
          mixBlendMode: "overlay",
        }}
      />
    </div>
  );
};

/** ALPHA EDGE: letters close in from a wide tracking, gold light runs across. */
export const Wordmark: React.FC<{ size: number; start: number; text?: string }> = ({ size, start, text = BRAND.product }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const t = frame / fps - start;
  const letters = [...text];
  const track = interpolate(t, [0, 1.4], [0.55, 0.16], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: EASE.out });
  const shine = interpolate(t, [0.6, 2.4], [0, 100], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  return (
    <div style={{ display: "flex", justifyContent: "center", fontFamily: F.display, fontWeight: 800, fontSize: size, letterSpacing: `${track}em`, marginRight: `-${track}em`, lineHeight: 1 }}>
      {letters.map((ch, i) => {
        const d = Math.abs(i - (letters.length - 1) / 2) * 0.05;
        const o = interpolate(t, [d, d + 0.6], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: EASE.out });
        const y = interpolate(t, [d, d + 0.8], [0.35, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: EASE.out });
        return (
          <span
            key={i}
            style={{
              display: "inline-block",
              opacity: o,
              transform: `translateY(${y}em)`,
              backgroundImage: goldGradient,
              backgroundSize: "300% 100%",
              backgroundPosition: `${100 - shine}% 0`,
              WebkitBackgroundClip: "text",
              backgroundClip: "text",
              color: "transparent",
              filter: `drop-shadow(0 0 ${size * 0.12}px rgba(234,214,166,0.22))`,
              whiteSpace: "pre",
            }}
          >
            {ch}
          </span>
        );
      })}
    </div>
  );
};

/** A thin gold line drawn from the centre outwards. */
export const GoldRule: React.FC<{ width: number; start: number; dur?: number; opacity?: number }> = ({ width, start, dur = 0.9, opacity = 1 }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = interpolate(frame / fps - start, [0, dur], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: EASE.out });
  return (
    <div style={{ width, height: 1.5, margin: "0 auto", opacity, background: `linear-gradient(90deg, transparent, ${C.gold} 20%, ${C.goldLight} 50%, ${C.gold} 80%, transparent)`, transform: `scaleX(${p})` }} />
  );
};

/** Text that rises out of a mask. */
export const Reveal: React.FC<{ start: number; dur?: number; children: React.ReactNode; style?: React.CSSProperties; from?: number }> = ({ start, dur = 0.8, children, style, from = 1 }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = interpolate(frame / fps - start, [0, dur], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: EASE.out });
  return (
    <div style={{ overflow: "hidden", ...style }}>
      <div style={{ transform: `translateY(${(1 - p) * 110 * from}%)`, opacity: Math.min(1, p * 1.6) }}>{children}</div>
    </div>
  );
};
