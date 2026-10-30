// The narration on screen, synchronised with the voice-over (and the SRT files).
import { interpolate, useCurrentFrame, useVideoConfig } from "remotion";
import type { AbsCaption } from "../lib/timeline";
import { fr } from "../lib/text";
import { F } from "../theme";

export const Captions: React.FC<{ items: AbsCaption[] }> = ({ items }) => {
  const frame = useCurrentFrame();
  const { fps, width, height } = useVideoConfig();
  const t = frame / fps;
  const c = items.find((x) => t >= x.start && t < x.end);
  if (!c) return null;
  const o = Math.min(
    interpolate(t, [c.start, c.start + 0.18], [0, 1], { extrapolateRight: "clamp" }),
    interpolate(t, [c.end - 0.18, c.end], [1, 0], { extrapolateLeft: "clamp" }),
  );
  const portrait = height > width;
  return (
    <div style={{ position: "absolute", left: 0, right: 0, bottom: portrait ? 72 : 34, display: "flex", justifyContent: "center", opacity: o, pointerEvents: "none" }}>
      <div
        style={{
          maxWidth: portrait ? 940 : 1480,
          padding: portrait ? "14px 26px" : "10px 26px",
          borderRadius: 14,
          background: "rgba(5,5,6,0.72)",
          border: "1px solid rgba(212,179,116,0.16)",
          fontFamily: F.body,
          fontWeight: 500,
          fontSize: portrait ? 40 : 31,
          lineHeight: 1.32,
          color: "#F5F2EA",
          textAlign: "center",
          textShadow: "0 2px 8px rgba(0,0,0,0.8)",
          transform: `translateY(${(1 - o) * 6}px)`,
        }}
      >
        {fr(c.text)}
      </div>
    </div>
  );
};
