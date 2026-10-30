// Chapter cards between the parts of the film: number, English kicker, French title.
import { AbsoluteFill, interpolate, useCurrentFrame, useVideoConfig } from "remotion";
import { Backdrop, Grain } from "../components/Backdrop";
import { Reveal } from "../components/Logo";
import type { Chapter } from "../content/types";
import { C, EASE, F } from "../theme";

export const ChapterScene: React.FC<{ chapter: Chapter }> = ({ chapter }) => {
  const frame = useCurrentFrame();
  const { fps, width, height } = useVideoConfig();
  const t = frame / fps;
  const portrait = height > width;
  const line = interpolate(t, [0.15, 0.9], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: EASE.out });
  const drift = interpolate(t, [0, 2.4], [0, -40]);
  const numO = interpolate(t, [0, 0.6], [0, 1], { extrapolateRight: "clamp" });
  return (
    <AbsoluteFill>
      <Backdrop glow={0.6} />
      <div
        style={{
          position: "absolute",
          right: portrait ? undefined : 120 - drift,
          left: portrait ? 0 : undefined,
          width: portrait ? "100%" : undefined,
          textAlign: portrait ? "center" : "right",
          top: portrait ? 300 : 120,
          fontFamily: F.display,
          fontWeight: 800,
          fontSize: portrait ? 460 : 520,
          lineHeight: 1,
          color: "transparent",
          WebkitTextStroke: `1.5px rgba(212,179,116,${0.22 * numO})`,
        }}
      >
        {chapter.n}
      </div>
      <div style={{ position: "absolute", left: portrait ? 80 : 180, right: portrait ? 80 : undefined, top: portrait ? 1020 : 420, textAlign: portrait ? "center" : "left" }}>
        <Reveal start={0.05} dur={0.6}>
          <div style={{ fontFamily: F.mono, fontSize: portrait ? 28 : 22, letterSpacing: "0.38em", color: C.gold }}>{chapter.kicker}</div>
        </Reveal>
        <div style={{ height: 22 }} />
        <div style={{ width: portrait ? 160 : 220, height: 1.5, background: C.gold, transform: `scaleX(${line})`, transformOrigin: portrait ? "50% 50%" : "0 50%", margin: portrait ? "0 auto" : undefined }} />
        <div style={{ height: 30 }} />
        <Reveal start={0.2} dur={0.8}>
          <div style={{ fontFamily: F.display, fontWeight: 800, fontSize: portrait ? 80 : 84, lineHeight: 1.06, color: C.white, maxWidth: portrait ? undefined : 1100 }}>{chapter.title}</div>
        </Reveal>
      </div>
      <Grain />
    </AbsoluteFill>
  );
};
