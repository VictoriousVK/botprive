// Frames for the captures: a desktop window and a phone, black with a gold hairline.
import { C, F } from "../theme";
import type { Rect } from "../lib/tour";

export const BAR = 34;

export const WindowFrame: React.FC<{ area: Rect; url: string; children: React.ReactNode; style?: React.CSSProperties }> = ({ area, url, children, style }) => (
  <div
    style={{
      position: "absolute",
      left: area.x,
      top: area.y - BAR,
      width: area.w,
      height: area.h + BAR,
      borderRadius: 16,
      overflow: "hidden",
      background: C.panel,
      border: `1px solid ${C.hair}`,
      // Short shadows: large blur radii are costly in software rendering.
      boxShadow: "0 22px 50px -18px rgba(0,0,0,0.9), 0 0 0 1px rgba(0,0,0,0.6)",
      ...style,
    }}
  >
    <div style={{ height: BAR, display: "flex", alignItems: "center", gap: 8, padding: "0 14px", background: "linear-gradient(180deg, #14161C, #0E1015)", borderBottom: `1px solid ${C.hairSoft}` }}>
      {["#3A3D45", "#3A3D45", "#3A3D45"].map((c, i) => (
        <span key={i} style={{ width: 11, height: 11, borderRadius: 6, background: c }} />
      ))}
      <div style={{ flex: 1, display: "flex", justifyContent: "center" }}>
        <span style={{ fontFamily: F.mono, fontSize: 13, color: C.grey, background: "rgba(255,255,255,0.04)", border: `1px solid ${C.hairSoft}`, borderRadius: 8, padding: "3px 16px", minWidth: 260, textAlign: "center" }}>
          {url}
        </span>
      </div>
      <span style={{ fontFamily: F.mono, fontSize: 11, letterSpacing: "0.2em", color: C.gold }}>DÉMO</span>
    </div>
    <div style={{ position: "relative", width: area.w, height: area.h, overflow: "hidden", background: "#03050a" }}>{children}</div>
    <div style={{ position: "absolute", inset: 0, pointerEvents: "none", background: "linear-gradient(160deg, rgba(255,255,255,0.05), transparent 28%)" }} />
  </div>
);

export const PHONE_BEZEL = 14;

export const PhoneFrame: React.FC<{ area: Rect; children: React.ReactNode; style?: React.CSSProperties }> = ({ area, children, style }) => (
  <div
    style={{
      position: "absolute",
      left: area.x - PHONE_BEZEL,
      top: area.y - PHONE_BEZEL,
      width: area.w + PHONE_BEZEL * 2,
      height: area.h + PHONE_BEZEL * 2,
      borderRadius: 64,
      background: "linear-gradient(160deg, #1A1C22, #08090C)",
      border: `1.5px solid ${C.hair}`,
      boxShadow: "0 26px 60px -20px rgba(0,0,0,0.95)",
      ...style,
    }}
  >
    <div style={{ position: "absolute", left: PHONE_BEZEL, top: PHONE_BEZEL, width: area.w, height: area.h, borderRadius: 52, overflow: "hidden", background: "#03050a" }}>{children}</div>
    <div style={{ position: "absolute", left: "50%", top: PHONE_BEZEL + 14, width: 120, height: 32, marginLeft: -60, borderRadius: 18, background: "#000" }} />
    <div style={{ position: "absolute", inset: 0, borderRadius: 64, pointerEvents: "none", background: "linear-gradient(150deg, rgba(255,255,255,0.08), transparent 30%)" }} />
  </div>
);
