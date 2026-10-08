// The black stage: a deep gradient, two slow gold glows, film grain, an optional grid.
// Rendering is software-only on most machines: the static part (gradient, grid, vignette) is drawn
// once into an image, and only cheap layers move (transforms, opacity).
import { useMemo } from "react";
import { AbsoluteFill, random, useCurrentFrame, useVideoConfig } from "remotion";
import { C } from "../theme";

/** Draws once, returns a data URL (deterministic). */
function useCanvas(w: number, h: number, key: string, draw: (ctx: CanvasRenderingContext2D) => void) {
  return useMemo(() => {
    if (typeof document === "undefined") return "";
    const c = document.createElement("canvas");
    c.width = w;
    c.height = h;
    const ctx = c.getContext("2d");
    if (!ctx) return "";
    draw(ctx);
    return c.toDataURL("image/png");
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [w, h, key]);
}

/** Film grain: four pre-drawn tiles, one per frame in turn, at low opacity. */
export const Grain: React.FC<{ opacity?: number }> = ({ opacity = 0.05 }) => {
  const frame = useCurrentFrame();
  const size = 192;
  const tile = useCanvas(size * 2, size * 2, "grain", (ctx) => {
    const img = ctx.createImageData(size * 2, size * 2);
    for (let i = 0; i < size * size * 4; i++) {
      const v = Math.floor(random(`grain-${i}`) * 255);
      img.data[i * 4] = v;
      img.data[i * 4 + 1] = v;
      img.data[i * 4 + 2] = v;
      img.data[i * 4 + 3] = 255;
    }
    ctx.putImageData(img, 0, 0);
  });
  if (!tile) return null;
  const k = frame % 4;
  const ox = (k % 2) * size + Math.floor(random(`gx-${frame}`) * 40);
  const oy = Math.floor(k / 2) * size + Math.floor(random(`gy-${frame}`) * 40);
  return <AbsoluteFill style={{ backgroundImage: `url(${tile})`, backgroundPosition: `-${ox}px -${oy}px`, opacity: opacity * 0.6, pointerEvents: "none" }} />;
};

export const Backdrop: React.FC<{ grid?: boolean; glow?: number }> = ({ grid = false, glow = 1 }) => {
  const frame = useCurrentFrame();
  const { width, height, fps } = useVideoConfig();
  const t = frame / fps;
  const portrait = height > width;
  const base = useCanvas(width, height, `base-${grid}-${portrait}`, (ctx) => {
    ctx.fillStyle = C.black;
    ctx.fillRect(0, 0, width, height);
    const r = Math.max(width, height) * 0.6;
    const g = ctx.createRadialGradient(width / 2, height / 2, 0, width / 2, height / 2, r);
    g.addColorStop(0, "#0C0D11");
    g.addColorStop(1, C.black);
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, width, height);
    if (grid) {
      const cell = Math.round(width / 24);
      const layer = document.createElement("canvas");
      layer.width = width;
      layer.height = height;
      const lc = layer.getContext("2d");
      if (lc) {
        lc.strokeStyle = "rgba(212,179,116,0.06)";
        lc.lineWidth = 1;
        for (let x = 0.5; x < width; x += cell) {
          lc.beginPath();
          lc.moveTo(x, 0);
          lc.lineTo(x, height);
          lc.stroke();
        }
        for (let y = 0.5; y < height; y += cell) {
          lc.beginPath();
          lc.moveTo(0, y);
          lc.lineTo(width, y);
          lc.stroke();
        }
        lc.globalCompositeOperation = "destination-in";
        const m = lc.createRadialGradient(width / 2, height / 2, 0, width / 2, height / 2, Math.max(width, height) * 0.55);
        m.addColorStop(0.2, "rgba(0,0,0,1)");
        m.addColorStop(1, "rgba(0,0,0,0)");
        lc.fillStyle = m;
        lc.fillRect(0, 0, width, height);
        ctx.drawImage(layer, 0, 0);
      }
    }
    const v = ctx.createRadialGradient(width / 2, height / 2, Math.min(width, height) * 0.45, width / 2, height / 2, Math.max(width, height) * 0.72);
    v.addColorStop(0, "rgba(0,0,0,0)");
    v.addColorStop(1, "rgba(0,0,0,0.65)");
    ctx.fillStyle = v;
    ctx.fillRect(0, 0, width, height);
  });
  const blob = (x: number, y: number, size: number, color: string, alpha: number) => (
    <div
      style={{
        position: "absolute",
        left: 0,
        top: 0,
        width: size,
        height: size,
        borderRadius: "50%",
        transform: `translate(${x - size / 2}px, ${y - size / 2}px)`,
        background: `radial-gradient(circle, ${color.replace("A", String(alpha))} 0%, transparent 68%)`,
        willChange: "transform",
      }}
    />
  );
  const s = Math.max(width, height);
  return (
    <AbsoluteFill style={{ background: C.black, overflow: "hidden" }}>
      {base && <AbsoluteFill style={{ backgroundImage: `url(${base})` }} />}
      {blob(width * (0.22 + Math.sin(t * 0.11) * 0.06), height * (0.3 + Math.cos(t * 0.09) * 0.05), s * 0.75, "rgba(212,179,116,A)", 0.085 * glow)}
      {blob(width * (0.78 + Math.cos(t * 0.07) * 0.06), height * (0.74 + Math.sin(t * 0.08) * 0.05), s * 0.7, "rgba(156,120,56,A)", 0.07 * glow)}
    </AbsoluteFill>
  );
};
