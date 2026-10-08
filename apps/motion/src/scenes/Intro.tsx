// Scene 1: darkness, chart fragments rushing towards the camera, a gold flare, the logo.
import { AbsoluteFill, interpolate, useCurrentFrame, useVideoConfig } from "remotion";
import { Backdrop, Grain } from "../components/Backdrop";
import { CandleField } from "../components/CandleField";
import { Emblem, GoldRule, Reveal, Wordmark } from "../components/Logo";
import { BRAND } from "../content/brand";
import { C, EASE, F } from "../theme";

export const IntroScene: React.FC<{ short?: boolean }> = ({ short }) => {
  const frame = useCurrentFrame();
  const { fps, width, height } = useVideoConfig();
  const t = frame / fps;
  const portrait = height > width;
  const T = short
    ? { flyStart: 0, flyEnd: 2.9, flare: 2.95, emblem: 3.0, word: 3.2, rule: 3.8, tag: 4.1, by: 4.6 }
    : { flyStart: 0.8, flyEnd: 7.5, flare: 7.55, emblem: 7.6, word: 7.85, rule: 8.7, tag: 9.3, by: 10.0 };
  const fly = interpolate(t, [T.flyStart, T.flyEnd], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: (x) => x * x * (3 - 2 * x) * 0.55 + x * x * x * 0.45 });
  const fieldOpacity = interpolate(t, [T.flyStart, T.flyStart + 1.2, T.flyEnd - 0.3, T.flyEnd + 0.4], [0, 1, 1, 0.12], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const flare = interpolate(t, [T.flare - 0.15, T.flare + 0.1, T.flare + 0.9], [0, 1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const flash = interpolate(t, [T.flare - 0.05, T.flare + 0.05, T.flare + 0.45], [0, 0.55, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const push = interpolate(t, [T.emblem, T.emblem + 6], [1, 1.035], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const logoSize = portrait ? 230 : 190;
  const wordSize = portrait ? 104 : 128;

  return (
    <AbsoluteFill>
      <Backdrop glow={interpolate(t, [T.flare, T.flare + 1.5], [0.3, 1.1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" })} />
      <CandleField progress={fly} opacity={fieldOpacity} />
      {/* fragments of the product vocabulary, before the logo */}
      {!short &&
        [
          ["LIQUIDITY", 0.24, 0.3, 2.0],
          ["FAIR VALUE GAP", 0.7, 0.62, 3.1],
          ["KILLZONE · NY AM", 0.3, 0.72, 4.2],
          ["RISK 1.00 %", 0.74, 0.26, 5.0],
        ].map(([txt, x, y, at]) => {
          const o = interpolate(t, [Number(at), Number(at) + 0.5, Number(at) + 1.6, Number(at) + 2.1], [0, 1, 1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
          return (
            <div key={String(txt)} style={{ position: "absolute", left: `${Number(x) * 100}%`, top: `${Number(y) * 100}%`, transform: "translate(-50%, -50%)", opacity: o, fontFamily: F.mono, fontSize: portrait ? 26 : 20, letterSpacing: "0.32em", color: C.goldLight }}>
              <span style={{ display: "inline-block", width: 8, height: 8, borderRadius: 4, background: C.gold, marginRight: 14, boxShadow: `0 0 12px ${C.gold}` }} />
              {txt}
            </div>
          );
        })}
      {/* flare */}
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", pointerEvents: "none" }}>
        <div style={{ width: width * (0.2 + flare * 0.9), height: 3, opacity: flare, background: `linear-gradient(90deg, transparent, ${C.goldLight}, #FFFBEF, ${C.goldLight}, transparent)`, boxShadow: `0 0 40px 8px rgba(234,214,166,${0.6 * flare})` }} />
      </AbsoluteFill>
      <AbsoluteFill style={{ background: "#FFF6E0", opacity: flash, mixBlendMode: "screen" }} />
      {/* logo */}
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", transform: `scale(${push})` }}>
        <div style={{ display: "flex", flexDirection: "column", alignItems: "center" }}>
          <Emblem size={logoSize} start={T.emblem} />
          <div style={{ height: portrait ? 56 : 44 }} />
          <Wordmark size={wordSize} start={T.word} />
          <div style={{ height: portrait ? 40 : 34 }} />
          <GoldRule width={portrait ? 520 : 620} start={T.rule} />
          <div style={{ height: portrait ? 40 : 30 }} />
          <Reveal start={T.tag} dur={0.9}>
            <div style={{ fontFamily: F.body, fontWeight: 300, fontSize: portrait ? 44 : 38, letterSpacing: "0.06em", color: C.white, textAlign: "center", padding: "0 40px" }}>{BRAND.taglineIntro}</div>
          </Reveal>
          <div style={{ height: 22 }} />
          <div
            style={{
              fontFamily: F.mono,
              fontSize: portrait ? 22 : 17,
              letterSpacing: "0.34em",
              color: C.dim,
              opacity: interpolate(t, [T.by, T.by + 0.8], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: EASE.out }),
              textTransform: "uppercase",
            }}
          >
            {BRAND.byline}
          </div>
        </div>
      </AbsoluteFill>
      <Grain />
    </AbsoluteFill>
  );
};
