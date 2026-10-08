// The black stage: a deep gradient, two slow gold glows, film grain, an optional grid.
import { useMemo } from "react";
import { AbsoluteFill, random, useCurrentFrame, useVideoConfig } from "remotion";
import { C } from "../theme";

/** A tile of film grain drawn once (deterministic), shifted every frame. */
function useGrainTile(seed = "grain") {
  return useMemo(() => {
    if (typeof document === "undefined") return "";
    const size = 160;
    const c = document.createElement("canvas");
    c.width = size;
    c.height = size;
    const ctx = c.getContext("2d");
    if (!ctx) return "";
    const img = ctx.createImageData(size, size);
    for (let i = 0; i < size * size; i++) {
      const v = Math.floor(random(`${seed}-${i}`) * 255);
      img.data[i * 4] = v;
      img.data[i * 4 + 1] = v;
      img.data[i * 4 + 2] = v;
      img.data[i * 4 + 3] = 255;
    }
    ctx.putImageData(img, 0, 0);
    return c.toDataURL("image/png");
  }, [seed]);
}

export const Grain: React.FC<{ opacity?: number }> = ({ opacity = 0.045 }) => {
  const frame = useCurrentFrame();
  const tile = useGrainTile();
  if (!tile) return null;
  const ox = Math.floor(random(`gx-${frame}`) * 160);
  const oy = Math.floor(random(`gy-${frame}`) * 160);
  return <AbsoluteFill style={{ backgroundImage: `url(${tile})`, backgroundPosition: `${ox}px ${oy}px`, opacity, mixBlendMode: "screen", pointerEvents: "none" }} />;
};

export const Backdrop: React.FC<{ grid?: boolean; glow?: number }> = ({ grid = false, glow = 1 }) => {
  const frame = useCurrentFrame();
  const { width, height, fps } = useVideoConfig();
  const t = frame / fps;
  const g1x = 22 + Math.sin(t * 0.11) * 6;
  const g1y = 30 + Math.cos(t * 0.09) * 5;
  const g2x = 78 + Math.cos(t * 0.07) * 6;
  const g2y = 74 + Math.sin(t * 0.08) * 5;
  return (
    <AbsoluteFill style={{ background: C.black }}>
      <AbsoluteFill
        style={{
          background: `radial-gradient(ellipse 55% 45% at ${g1x}% ${g1y}%, rgba(212,179,116,${0.09 * glow}), transparent 70%),
            radial-gradient(ellipse 50% 45% at ${g2x}% ${g2y}%, rgba(156,120,56,${0.07 * glow}), transparent 70%),
            radial-gradient(ellipse 80% 70% at 50% 50%, #0B0C10 0%, ${C.black} 75%)`,
        }}
      />
      {grid && (
        <AbsoluteFill
          style={{
            backgroundImage: `linear-gradient(rgba(212,179,116,0.05) 1px, transparent 1px), linear-gradient(90deg, rgba(212,179,116,0.05) 1px, transparent 1px)`,
            backgroundSize: `${Math.round(width / 24)}px ${Math.round(width / 24)}px`,
            backgroundPosition: `${(t * 6) % (width / 24)}px 0px`,
            maskImage: "radial-gradient(ellipse 70% 60% at 50% 50%, #000 20%, transparent 80%)",
            WebkitMaskImage: "radial-gradient(ellipse 70% 60% at 50% 50%, #000 20%, transparent 80%)",
          }}
        />
      )}
      <AbsoluteFill style={{ background: `radial-gradient(ellipse ${width > height ? "75% 85%" : "95% 70%"} at 50% 50%, transparent 55%, rgba(0,0,0,0.65) 100%)` }} />
    </AbsoluteFill>
  );
};
