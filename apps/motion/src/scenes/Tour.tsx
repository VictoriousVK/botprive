// A tour of the real product: captures in a window (or a phone), a camera that frames each zone,
// a gold frame and a spotlight on what is explained, a cursor that clicks, and a note beside the
// screen joined to the zone by a hairline.
import { useMemo } from "react";
import { AbsoluteFill, Img, interpolate, useCurrentFrame, useVideoConfig } from "remotion";
import { BAR, PhoneFrame, WindowFrame } from "../components/Chrome";
import { Cursor } from "../components/Cursor";
import { Backdrop } from "../components/Backdrop";
import type { Chapter, Note, Step } from "../content/types";
import { shotSrc, useManifest, type Manifest } from "../lib/captures";
import { boxOf, buildModel, camAt, cursorAt, ease, focusAt, notes, pageTransform, SHOT_FADE, shotIndexAt, toScreen, type Model, type Rect } from "../lib/tour";
import { C, EASE, F } from "../theme";

const clamp01 = (v: number) => Math.min(1, Math.max(0, v));
const lerpRect = (a: Rect, b: Rect, p: number): Rect => ({ x: a.x + (b.x - a.x) * p, y: a.y + (b.y - a.y) * p, w: a.w + (b.w - a.w) * p, h: a.h + (b.h - a.h) * p });

type Layout = { kind: "window" | "phone"; full: Rect; split: Rect };

function layoutFor(width: number, height: number, device: "window" | "phone" | undefined): Layout {
  if (height > width) {
    const cw = 580;
    const ch = Math.round((cw * 844) / 390);
    const area = { x: Math.round((width - cw) / 2), y: 236, w: cw, h: ch };
    return { kind: "phone", full: area, split: area };
  }
  if (device === "phone") {
    const ch = 860;
    const cw = Math.round((ch * 390) / 844);
    const area = { x: 1180, y: 110, w: cw, h: ch };
    return { kind: "phone", full: area, split: area };
  }
  return { kind: "window", full: { x: 240, y: 98, w: 1440, h: 900 }, split: { x: 556, y: 98, w: 1296, h: 810 } };
}

export const TourScene: React.FC<{ steps: Step[]; dur: number; chapter: Chapter; device?: "window" | "phone"; tag?: string }> = ({ steps, dur, chapter, device, tag }) => {
  const frame = useCurrentFrame();
  const { fps, width, height } = useVideoConfig();
  const t = frame / fps;
  const man = useManifest();
  const model = useMemo(() => buildModel(steps), [steps]);
  const L = layoutFor(width, height, device);
  const noteList = useMemo(() => notes(model, dur), [model, dur]);
  const firstNote = noteList[0]?.at ?? Infinity;
  const split = L.kind === "window" ? ease(clamp01((t - firstNote) / 0.8)) : 0;
  const area = lerpRect(L.full, L.split, split);
  const ent = interpolate(t, [0, 0.9], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: EASE.out });

  const content = man ? <Screen man={man} model={model} area={area} t={t} tag={tag} /> : <Missing />;
  const frameStyle: React.CSSProperties = { opacity: ent, transform: `perspective(1800px) rotateX(${(1 - ent) * 7}deg) translateY(${(1 - ent) * 36}px)`, transformOrigin: "50% 100%" };
  const url = man ? man.shots[model.shots[shotIndexAt(model, t)]?.name]?.url ?? "" : "";

  return (
    <AbsoluteFill>
      <Backdrop grid glow={0.8} />
      {L.kind === "window" ? (
        <WindowFrame area={area} url={url} style={frameStyle}>
          {content}
        </WindowFrame>
      ) : (
        <PhoneFrame area={area} style={frameStyle}>
          {content}
        </PhoneFrame>
      )}
      {L.kind === "window" ? <SideNotes chapter={chapter} notes={noteList} t={t} split={split} man={man} model={model} area={area} /> : <BottomNotes chapter={chapter} notes={noteList} t={t} area={area} />}
    </AbsoluteFill>
  );
};

const Missing: React.FC = () => (
  <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", fontFamily: F.mono, color: C.gold, fontSize: 22, textAlign: "center", padding: 40 }}>
    Captures du produit absentes : lancez « npm run capture » dans apps/motion.
  </AbsoluteFill>
);

/** The captured page under the camera, the frame, the spotlight and the cursor. */
const Screen: React.FC<{ man: Manifest; model: Model; area: Rect; t: number; tag?: string }> = ({ man, model, area, t, tag }) => {
  const local = { x: 0, y: 0, w: area.w, h: area.h };
  const i = shotIndexAt(model, t);
  const cur = model.shots[i];
  const since = t - cur.at;
  const layers: { idx: number; opacity: number; scale: number }[] = [];
  if (i > 0 && since < SHOT_FADE) layers.push({ idx: i - 1, opacity: 1, scale: 1 });
  const fadeIn = i > 0 ? ease(clamp01(since / SHOT_FADE)) : 1;
  layers.push({ idx: i, opacity: fadeIn, scale: 1 + 0.014 * (1 - fadeIn) });

  const f = focusAt(model, t);
  const shot = man.shots[cur.name];
  let frameRect: Rect | null = null;
  let fIn = 0;
  let fOut = 1;
  let spot = false;
  if (f && f.until > t && shotIndexAt(model, f.at) === i && shot) {
    const b = boxOf(f.target, shot);
    if (b) {
      const r = toScreen(b, camAt(model, man, i, t, area.w, area.h), shot, local);
      const pad = 8;
      frameRect = { x: r.x - pad, y: r.y - pad, w: r.w + pad * 2, h: r.h + pad * 2 };
      fIn = ease(clamp01((t - f.at) / 0.6));
      fOut = clamp01((f.until - t) / 0.3);
      spot = f.spot;
    }
  }
  const cursor = cursorAt(model, man, t, local, area.w, area.h);

  return (
    <AbsoluteFill>
      {layers.map(({ idx, opacity, scale }) => {
        const s = man.shots[model.shots[idx].name];
        if (!s) return <Missing key={idx} />;
        const cam = camAt(model, man, idx, t, area.w, area.h);
        const { S, tx, ty } = pageTransform(cam, s, local);
        return (
          <div key={idx} style={{ position: "absolute", inset: 0, opacity, transform: `scale(${scale})`, transformOrigin: "50% 50%" }}>
            <Img src={shotSrc(s)} style={{ position: "absolute", left: 0, top: 0, width: s.width, height: s.height, transform: `translate(${tx}px, ${ty}px) scale(${S})`, transformOrigin: "0 0" }} />
          </div>
        );
      })}
      {frameRect && <Spotlight r={frameRect} w={area.w} h={area.h} pIn={fIn} pOut={fOut} dim={spot} />}
      {tag && <TagPill text={tag} />}
      {cursor && <Cursor x={cursor.x} y={cursor.y} click={cursor.click} />}
    </AbsoluteFill>
  );
};

const Spotlight: React.FC<{ r: Rect; w: number; h: number; pIn: number; pOut: number; dim: boolean }> = ({ r, w, h, pIn, pOut, dim }) => {
  const a = Math.min(pIn, pOut);
  const rad = 12;
  const per = 2 * (r.w + r.h);
  const hole = `M0 0 H${w} V${h} H0 Z M${r.x + rad} ${r.y} H${r.x + r.w - rad} Q${r.x + r.w} ${r.y} ${r.x + r.w} ${r.y + rad} V${r.y + r.h - rad} Q${r.x + r.w} ${r.y + r.h} ${r.x + r.w - rad} ${r.y + r.h} H${r.x + rad} Q${r.x} ${r.y + r.h} ${r.x} ${r.y + r.h - rad} V${r.y + rad} Q${r.x} ${r.y} ${r.x + rad} ${r.y} Z`;
  return (
    <svg width={w} height={h} style={{ position: "absolute", left: 0, top: 0, pointerEvents: "none" }}>
      {dim && <path d={hole} fill={`rgba(2,3,5,${0.5 * a})`} fillRule="evenodd" />}
      <rect x={r.x} y={r.y} width={r.w} height={r.h} rx={rad} fill="none" stroke={C.goldLight} strokeOpacity={0.35 * pOut} strokeWidth={8} style={{ filter: "blur(6px)" }} strokeDasharray={per} strokeDashoffset={per * (1 - pIn)} />
      <rect x={r.x} y={r.y} width={r.w} height={r.h} rx={rad} fill="none" stroke={C.gold} strokeOpacity={pOut} strokeWidth={2.2} strokeDasharray={per} strokeDashoffset={per * (1 - pIn)} />
    </svg>
  );
};

const TagPill: React.FC<{ text: string }> = ({ text }) => (
  <div style={{ position: "absolute", right: 16, bottom: 16, padding: "6px 14px", borderRadius: 999, background: "rgba(5,5,6,0.82)", border: `1px solid ${C.hair}`, fontFamily: F.mono, fontSize: 14, letterSpacing: "0.16em", color: C.gold, textTransform: "uppercase" }}>
    {text}
  </div>
);

/** A note: kicker, title, one line; it enters with the frame and leaves when the next one comes. */
const NoteCard: React.FC<{ note: Note; at: number; until: number; t: number; center?: boolean; size?: number }> = ({ note, at, until, t, center, size = 1 }) => {
  const pIn = clamp01((t - at) / 0.7);
  const out = clamp01((until - t) / 0.25);
  const k = EASE.out(clamp01(pIn / 0.6));
  const ti = EASE.out(clamp01((pIn - 0.1) / 0.7));
  const tx = EASE.out(clamp01((pIn - 0.3) / 0.7));
  return (
    <div style={{ position: "absolute", inset: 0, opacity: out, textAlign: center ? "center" : "left" }}>
      <div style={{ fontFamily: F.mono, fontSize: 15 * size, letterSpacing: "0.3em", color: C.gold, opacity: k, transform: `translateY(${(1 - k) * 10}px)` }}>{note.kicker}</div>
      <div style={{ overflow: "hidden", marginTop: 12 * size }}>
        <div style={{ fontFamily: F.display, fontWeight: 700, fontSize: 40 * size, lineHeight: 1.12, color: C.white, transform: `translateY(${(1 - ti) * 105}%)` }}>{note.title}</div>
      </div>
      {note.text && <div style={{ marginTop: 16 * size, fontFamily: F.body, fontSize: 24 * size, lineHeight: 1.45, color: C.grey, opacity: tx, transform: `translateY(${(1 - tx) * 8}px)` }}>{note.text}</div>}
    </div>
  );
};

const NOTE_X = 84;
const NOTE_W = 420;
const NOTE_Y = 300;

const SideNotes: React.FC<{ chapter: Chapter; notes: { at: number; until: number; note: Note }[]; t: number; split: number; man: Manifest | null; model: Model; area: Rect }> = ({ chapter, notes: list, t, split, man, model, area }) => {
  const active = list.filter((n) => t >= n.at && t < n.until);
  // Hairline from the note to the framed zone.
  let line: { x1: number; y1: number; x2: number; y2: number; p: number; o: number } | null = null;
  const f = focusAt(model, t);
  if (man && f && f.note && f.until > t) {
    const i = shotIndexAt(model, t);
    const shot = man.shots[model.shots[i].name];
    const b = boxOf(f.target, shot);
    if (shot && b && shotIndexAt(model, f.at) === i) {
      const r = toScreen(b, camAt(model, man, i, t, area.w, area.h), shot, area);
      const x2 = Math.max(area.x + 4, r.x - 8);
      const y2 = Math.min(area.y + area.h - 10, Math.max(area.y + 10, r.y + Math.min(r.h / 2, 60)));
      line = { x1: NOTE_X + NOTE_W + 12, y1: NOTE_Y + 78, x2, y2, p: ease(clamp01((t - f.at - 0.25) / 0.6)), o: clamp01((f.until - t) / 0.3) };
    }
  }
  return (
    <AbsoluteFill style={{ opacity: split }}>
      <div style={{ position: "absolute", left: NOTE_X, top: area.y - BAR, width: NOTE_W }}>
        <div style={{ display: "flex", alignItems: "baseline", gap: 14 }}>
          <span style={{ fontFamily: F.display, fontWeight: 800, fontSize: 30, color: C.gold }}>{chapter.n}</span>
          <span style={{ fontFamily: F.mono, fontSize: 14, letterSpacing: "0.28em", color: C.gold }}>{chapter.kicker}</span>
        </div>
        <div style={{ marginTop: 8, fontFamily: F.display, fontWeight: 600, fontSize: 22, lineHeight: 1.25, color: C.grey }}>{chapter.title}</div>
        <div style={{ marginTop: 18, width: 64, height: 1.5, background: C.gold, opacity: 0.6 }} />
      </div>
      <div style={{ position: "absolute", left: NOTE_X, top: NOTE_Y, width: NOTE_W, height: 420 }}>
        {active.map((n) => (
          <NoteCard key={n.at} note={n.note} at={n.at} until={n.until} t={t} />
        ))}
      </div>
      {line && (
        <svg width="100%" height="100%" style={{ position: "absolute", inset: 0, pointerEvents: "none", opacity: line.o }}>
          <line x1={line.x1} y1={line.y1} x2={line.x1 + (line.x2 - line.x1) * line.p} y2={line.y1 + (line.y2 - line.y1) * line.p} stroke={C.gold} strokeWidth={1.4} strokeOpacity={0.75} />
          <circle cx={line.x1} cy={line.y1} r={3.5} fill={C.gold} />
          {line.p > 0.98 && <circle cx={line.x2} cy={line.y2} r={4} fill={C.goldLight} />}
        </svg>
      )}
    </AbsoluteFill>
  );
};

const BottomNotes: React.FC<{ chapter: Chapter; notes: { at: number; until: number; note: Note }[]; t: number; area: Rect }> = ({ chapter, notes: list, t, area }) => {
  const { width, height } = useVideoConfig();
  const portrait = height > width;
  const active = list.filter((n) => t >= n.at && t < n.until);
  const head = clamp01(t / 0.6);
  if (!portrait) {
    return (
      <AbsoluteFill>
        <div style={{ position: "absolute", left: 160, top: 300, width: 760, height: 420 }}>
          {active.map((n) => (
            <NoteCard key={n.at} note={n.note} at={n.at} until={n.until} t={t} size={1.25} />
          ))}
        </div>
      </AbsoluteFill>
    );
  }
  return (
    <AbsoluteFill>
      <div style={{ position: "absolute", top: 96, left: 0, right: 0, textAlign: "center", opacity: head }}>
        <div style={{ fontFamily: F.mono, fontSize: 22, letterSpacing: "0.32em", color: C.gold }}>
          {chapter.n} · {chapter.kicker}
        </div>
      </div>
      <div style={{ position: "absolute", left: 80, right: 80, top: area.y + area.h + 46, height: 180 }}>
        {active.map((n) => (
          <NoteCard key={n.at} note={n.note} at={n.at} until={n.until} t={t} center size={1.3} />
        ))}
      </div>
    </AbsoluteFill>
  );
};
