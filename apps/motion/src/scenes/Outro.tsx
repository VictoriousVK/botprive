// Scene 10: the platform as a constellation of real screens, then the signature.
import { AbsoluteFill, Img, interpolate, useCurrentFrame, useVideoConfig } from "remotion";
import { Backdrop, Grain } from "../components/Backdrop";
import { CandleField } from "../components/CandleField";
import { Emblem, GoldRule, Reveal, Wordmark } from "../components/Logo";
import { BRAND } from "../content/brand";
import { shotSrc, useManifest } from "../lib/captures";
import { C, EASE, F } from "../theme";

const WALL = ["dashboard", "coach_verdict", "risque_ftmo", "analyse_card", "console_backtest"];

export const OutroScene: React.FC<{ short?: boolean }> = ({ short }) => {
  const frame = useCurrentFrame();
  const { fps, width, height, durationInFrames } = useVideoConfig();
  const t = frame / fps;
  const portrait = height > width;
  const man = useManifest();
  const T = short ? { logo: 0.1, word: 0.3, rule: 0.9, en: 1.2, fr: 1.8, contact: 2.4, wallOut: 0 } : { logo: 5.6, word: 5.85, rule: 6.6, en: 7.0, fr: 7.8, contact: 8.6, wallOut: 4.8 };
  const end = durationInFrames / fps;
  const fadeOut = interpolate(t, [end - 1.0, end], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const wallIn = EASE.out(Math.min(1, t / 1.2));
  const wallOut = short ? 1 : interpolate(t, [T.wallOut, T.wallOut + 1.4], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: EASE.cine });
  const orbit = interpolate(t, [0, 6], [-10, 6]);

  return (
    <AbsoluteFill style={{ opacity: fadeOut }}>
      <Backdrop glow={1} />
      {short && <CandleField progress={0.35 + t * 0.02} opacity={0.18} />}
      {!short && man && (
        <AbsoluteFill style={{ perspective: 1600, opacity: 1 - wallOut * 0.85 }}>
          <AbsoluteFill style={{ transformStyle: "preserve-3d", transform: `rotateY(${orbit}deg) translateZ(${-wallOut * 900}px)` }}>
            {WALL.map((name, i) => {
              const s = man.shots[name];
              if (!s) return null;
              const k = i - 2;
              const w = portrait ? 620 : 760;
              const h = w / 1.6;
              const appear = EASE.out(Math.min(1, Math.max(0, (t - i * 0.18) / 1.0)));
              return (
                <div
                  key={name}
                  style={{
                    position: "absolute",
                    left: width / 2 - w / 2 + (portrait ? k * 60 : k * 420),
                    top: height / 2 - h / 2 + (portrait ? k * 330 : (Math.abs(k) === 1 ? -70 : Math.abs(k) === 2 ? 60 : -10)),
                    width: w,
                    height: h,
                    opacity: appear * wallIn,
                    transform: `translateZ(${-Math.abs(k) * 260 + (1 - appear) * -400}px) rotateY(${portrait ? 0 : -k * 14}deg)`,
                    borderRadius: 14,
                    overflow: "hidden",
                    border: `1px solid ${C.hair}`,
                    boxShadow: "0 22px 50px -20px rgba(0,0,0,0.95)",
                    background: C.panel,
                  }}
                >
                  <Img src={shotSrc(s)} style={{ width: w, height: (w / s.width) * s.height }} />
                </div>
              );
            })}
          </AbsoluteFill>
        </AbsoluteFill>
      )}
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
        <div style={{ display: "flex", flexDirection: "column", alignItems: "center", textAlign: "center" }}>
          <Emblem size={portrait ? 200 : 150} start={T.logo} />
          <div style={{ height: 36 }} />
          <Wordmark size={portrait ? 100 : 112} start={T.word} />
          <div style={{ height: 30 }} />
          <GoldRule width={portrait ? 480 : 560} start={T.rule} />
          <div style={{ height: 30 }} />
          <Reveal start={T.en} dur={0.9}>
            <div style={{ fontFamily: F.display, fontWeight: 600, fontSize: portrait ? 50 : 46, color: C.white, padding: "0 40px" }}>{BRAND.taglineOutro}</div>
          </Reveal>
          <div style={{ height: 14 }} />
          <Reveal start={T.fr} dur={0.9}>
            <div style={{ fontFamily: F.body, fontWeight: 300, fontSize: portrait ? 34 : 28, color: C.grey, letterSpacing: "0.04em" }}>{BRAND.taglineOutroFr}</div>
          </Reveal>
          <div style={{ height: portrait ? 90 : 56 }} />
          <div style={{ opacity: interpolate(t, [T.contact, T.contact + 0.8], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" }), display: "flex", flexDirection: "column", gap: 12, alignItems: "center" }}>
            {BRAND.siteUrl && <div style={{ fontFamily: F.mono, fontSize: portrait ? 34 : 28, letterSpacing: "0.12em", color: C.goldLight }}>{BRAND.siteUrl}</div>}
            <div style={{ fontFamily: F.mono, fontSize: portrait ? 26 : 20, letterSpacing: "0.16em", color: C.gold }}>{BRAND.contact}</div>
            <div style={{ marginTop: 10, maxWidth: portrait ? 860 : 1100, fontFamily: F.body, fontSize: portrait ? 20 : 16, lineHeight: 1.5, color: C.dim }}>{BRAND.disclaimer}</div>
          </div>
        </div>
      </AbsoluteFill>
      <Grain />
    </AbsoluteFill>
  );
};
