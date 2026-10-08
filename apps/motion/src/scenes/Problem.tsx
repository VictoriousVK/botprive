// Scene 2: what traders struggle with, as six cards that converge into one window: the platform.
import { ChartScatter, Hourglass, Layers, LibraryBig, ListChecks, ShieldAlert } from "lucide-react";
import { AbsoluteFill, Img, interpolate, useCurrentFrame, useVideoConfig } from "remotion";
import { Backdrop, Grain } from "../components/Backdrop";
import { shotSrc, useManifest } from "../lib/captures";
import { ease } from "../lib/tour";
import { C, EASE, F } from "../theme";

const CARDS = [
  { icon: Layers, kicker: "SCATTERED TOOLS", title: "Des outils dispersés", art: "windows" },
  { icon: ListChecks, kicker: "DISCIPLINE", title: "Un plan rarement vérifié", art: "checklist" },
  { icon: ChartScatter, kicker: "MEASUREMENT", title: "Des performances floues", art: "scatter" },
  { icon: Hourglass, kicker: "TIME", title: "Une analyse chronophage", art: "clock" },
  { icon: ShieldAlert, kicker: "RISK", title: "Un risque géré de tête", art: "drawdown" },
  { icon: LibraryBig, kicker: "KNOWLEDGE", title: "Un savoir éparpillé", art: "notes" },
] as const;

const clamp01 = (v: number) => Math.min(1, Math.max(0, v));

const Art: React.FC<{ kind: (typeof CARDS)[number]["art"]; t: number }> = ({ kind, t }) => {
  const W = 150;
  const H = 86;
  const s = { stroke: C.gold, strokeWidth: 1.6, fill: "none" } as const;
  switch (kind) {
    case "windows":
      return (
        <svg width={W} height={H}>
          {[0, 1, 2, 3].map((i) => (
            <rect key={i} x={8 + i * 26 + Math.sin(t * 2 + i) * 4} y={8 + (i % 2) * 22 + Math.cos(t * 1.7 + i) * 3} width={62} height={40} rx={5} stroke={C.gold} strokeWidth={1.6} strokeOpacity={0.35 + i * 0.15} fill="rgba(212,179,116,0.05)" />
          ))}
        </svg>
      );
    case "checklist":
      return (
        <svg width={W} height={H}>
          {[0, 1, 2].map((i) => (
            <g key={i}>
              <rect x={8} y={8 + i * 26} width={16} height={16} rx={3} {...s} />
              {i < 2 ? <path d={`M11 ${16 + i * 26} l4 4 l7 -8`} {...s} /> : <path d={`M11 ${11 + i * 26} l10 10 M21 ${11 + i * 26} l-10 10`} stroke={C.down} strokeWidth={1.8} opacity={0.5 + 0.5 * Math.abs(Math.sin(t * 3))} />}
              <line x1={34} x2={34 + 90 - i * 18} y1={16 + i * 26} y2={16 + i * 26} stroke={C.grey} strokeOpacity={0.5} strokeWidth={6} strokeLinecap="round" />
            </g>
          ))}
        </svg>
      );
    case "scatter":
      return (
        <svg width={W} height={H}>
          {Array.from({ length: 14 }, (_, i) => (
            <circle key={i} cx={10 + ((i * 37) % 130) + Math.sin(t * 1.3 + i) * 3} cy={10 + ((i * 53) % 66) + Math.cos(t + i) * 3} r={3} fill={C.gold} fillOpacity={0.35 + (i % 3) * 0.2} />
          ))}
          <text x={118} y={30} fill={C.goldLight} fontFamily={F.display} fontWeight={800} fontSize={30}>
            ?
          </text>
        </svg>
      );
    case "clock":
      return (
        <svg width={W} height={H}>
          <circle cx={45} cy={43} r={34} {...s} />
          <line x1={45} y1={43} x2={45 + 26 * Math.sin(t * 6)} y2={43 - 26 * Math.cos(t * 6)} stroke={C.goldLight} strokeWidth={2} />
          <line x1={45} y1={43} x2={45 + 16 * Math.sin(t * 0.5)} y2={43 - 16 * Math.cos(t * 0.5)} stroke={C.gold} strokeWidth={2.4} />
          <polyline points="90,60 104,44 116,52 130,30 142,38" {...s} strokeOpacity={0.6} />
        </svg>
      );
    case "drawdown":
      return (
        <svg width={W} height={H}>
          <line x1={4} x2={146} y1={66} y2={66} stroke={C.down} strokeDasharray="6 5" strokeWidth={1.4} />
          <polyline points={`6,24 26,18 44,30 62,26 80,44 98,40 116,58 ${132},${64 + Math.sin(t * 2) * 6}`} {...s} />
        </svg>
      );
    default:
      return (
        <svg width={W} height={H}>
          {[0, 1, 2].map((i) => (
            <g key={i} transform={`translate(${12 + i * 30}, ${6 + i * 10}) rotate(${(i - 1) * 8 + Math.sin(t + i) * 2})`}>
              <rect width={70} height={50} rx={5} fill="rgba(212,179,116,0.06)" stroke={C.gold} strokeWidth={1.6} strokeOpacity={0.4 + i * 0.2} />
              <polygon points="28,17 28,33 42,25" fill={C.gold} fillOpacity={0.5} />
            </g>
          ))}
        </svg>
      );
  }
};

export const ProblemScene: React.FC<{ short?: boolean }> = ({ short }) => {
  const frame = useCurrentFrame();
  const { fps, width, height } = useVideoConfig();
  const t = frame / fps;
  const man = useManifest();
  const portrait = height > width;
  const T = short ? { first: 0.15, gap: 0.22, conv: 2.5, convDur: 1.0, unfold: 3.5, msg: 4.2 } : { first: 0.6, gap: 1.25, conv: 13.6, convDur: 2.0, unfold: 15.6, msg: 16.8 };
  const conv = ease(clamp01((t - T.conv) / T.convDur));
  const core = interpolate(t, [T.conv + T.convDur * 0.4, T.unfold, T.unfold + 0.6], [0, 1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const ux = EASE.out(clamp01((t - T.unfold) / 0.5));
  const uy = EASE.out(clamp01((t - T.unfold - 0.35) / 0.45));
  const cw = portrait ? 940 : 1000;
  const ch = cw / 1.6;
  const wy = portrait ? 520 : 140;
  const shot = man?.shots.dashboard;
  const cardW = portrait ? 470 : 480;
  const cardH = portrait ? 300 : 250;

  return (
    <AbsoluteFill>
      <Backdrop grid glow={0.7} />
      {CARDS.map((c, i) => {
        const col = portrait ? i % 2 : i % 3;
        const row = portrait ? Math.floor(i / 2) : Math.floor(i / 3);
        const x0 = portrait ? 290 + col * 500 : 400 + col * 560;
        const y0 = portrait ? 520 + row * 340 : 340 + row * 330;
        const at = T.first + i * T.gap;
        const pIn = EASE.out(clamp01((t - at) / 0.8));
        const fx = x0 + Math.sin(t * 0.6 + i) * 6;
        const fy = y0 + Math.cos(t * 0.5 + i * 1.3) * 6;
        const x = fx + (width / 2 - fx) * conv;
        const y = fy + ((portrait ? wy + ch / 2 : wy + ch / 2) - fy) * conv;
        const s = (0.92 + 0.08 * pIn) * (1 - conv * 0.88);
        const o = pIn * (1 - clamp01((conv - 0.6) / 0.4));
        if (o <= 0.01) return null;
        const Icon = c.icon;
        return (
          <div
            key={c.kicker}
            style={{
              position: "absolute",
              left: x - cardW / 2,
              top: y - cardH / 2,
              width: cardW,
              height: cardH,
              opacity: o,
              transform: `perspective(1200px) rotateX(${(1 - pIn) * 24}deg) rotateZ(${conv * (i - 2.5) * 14}deg) translateY(${(1 - pIn) * 40}px) scale(${s})`,
              borderRadius: 18,
              background: "linear-gradient(160deg, rgba(24,26,33,0.92), rgba(10,11,14,0.92))",
              border: `1px solid ${C.hair}`,
              boxShadow: "0 30px 80px -30px rgba(0,0,0,0.9)",
              padding: 26,
            }}
          >
            <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
              <span style={{ width: 46, height: 46, borderRadius: 23, display: "grid", placeItems: "center", border: `1px solid ${C.hair}`, background: "rgba(212,179,116,0.08)" }}>
                <Icon size={24} color={C.gold} strokeWidth={1.6} />
              </span>
              <span style={{ fontFamily: F.mono, fontSize: 15, letterSpacing: "0.26em", color: C.gold }}>{c.kicker}</span>
            </div>
            <div style={{ marginTop: 18, fontFamily: F.display, fontWeight: 700, fontSize: portrait ? 34 : 31, lineHeight: 1.15, color: C.white, maxWidth: portrait ? 400 : 270 }}>{c.title}</div>
            <div style={{ position: "absolute", right: 22, bottom: 20 }}>
              <Art kind={c.art} t={t} />
            </div>
          </div>
        );
      })}
      {/* the core of light, then the window of the platform */}
      <div style={{ position: "absolute", left: width / 2 - 260, top: wy + ch / 2 - 260, width: 520, height: 520, borderRadius: "50%", background: `radial-gradient(circle, rgba(255,246,224,${0.85 * core}), rgba(212,179,116,${0.35 * core}) 30%, transparent 65%)` }} />
      {t >= T.unfold && (
        <div
          style={{
            position: "absolute",
            left: (width - cw) / 2,
            top: wy,
            width: cw,
            height: ch,
            transform: `scale(${Math.max(0.02, ux)}, ${Math.max(0.006, uy)})`,
            borderRadius: 14,
            overflow: "hidden",
            border: `1px solid ${C.hair}`,
            boxShadow: "0 40px 120px -30px rgba(0,0,0,0.95), 0 0 120px -30px rgba(212,179,116,0.35)",
            background: C.panel,
          }}
        >
          {shot && <Img src={shotSrc(shot)} style={{ width: cw, height: (cw / shot.width) * shot.height, opacity: uy }} />}
          <div style={{ position: "absolute", inset: 0, background: `linear-gradient(180deg, rgba(255,246,224,${0.5 * (1 - uy)}), transparent)` }} />
        </div>
      )}
      <div style={{ position: "absolute", left: portrait ? 60 : 160, right: portrait ? 60 : 160, top: wy + ch + (portrait ? 70 : 42), textAlign: "center" }}>
        {short ? (
          <Line t={t} at={T.msg} size={portrait ? 64 : 58}>
            Une seule <Gold>plateforme</Gold>.
          </Line>
        ) : (
          <Line t={t} at={T.msg} size={portrait ? 48 : 40}>
            Une plateforme pour <Gold>centraliser</Gold> vos outils, <Gold>structurer</Gold> votre analyse et mieux <Gold>comprendre</Gold> vos performances.
          </Line>
        )}
      </div>
      <Grain />
    </AbsoluteFill>
  );
};

const Gold: React.FC<{ children: React.ReactNode }> = ({ children }) => <span style={{ color: C.goldLight }}>{children}</span>;

const Line: React.FC<{ t: number; at: number; size: number; children: React.ReactNode }> = ({ t, at, size, children }) => {
  const p = EASE.out(clamp01((t - at) / 0.9));
  return (
    <div style={{ fontFamily: F.display, fontWeight: 600, fontSize: size, lineHeight: 1.28, color: C.white, opacity: p, transform: `translateY(${(1 - p) * 18}px)`, filter: `blur(${(1 - p) * 6}px)` }}>{children}</div>
  );
};
