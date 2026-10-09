// The camera, the frames and the cursor of a product tour, computed from the scene's steps.
// Coordinates: "page" = CSS pixels of the captured page; "screen" = pixels of the video frame.
import type { Box, Note, Step, Target, View } from "../content/types";
import type { Manifest, ShotInfo } from "./captures";

export type Rect = { x: number; y: number; w: number; h: number };
export type Cam = { cx: number; cy: number; z: number };

export const MAX_ZOOM = 2.2;
export const SHOT_FADE = 0.45;
export const VIEW_DUR = 1.1;
export const CURSOR_DUR = 0.8;

const clamp = (v: number, a: number, b: number) => Math.min(b, Math.max(a, v));
const lerp = (a: number, b: number, p: number) => a + (b - a) * p;
/** Ease in-out (cubic), used for every camera and cursor move. */
export const ease = (p: number) => (p < 0.5 ? 4 * p * p * p : 1 - Math.pow(-2 * p + 2, 3) / 2);

export type Model = {
  shots: { at: number; name: string; view?: View }[];
  views: { at: number; view: View; dur: number }[];
  focuses: { at: number; target: Target; note?: Note; spot: boolean }[];
  cursors: { at: number; target: Target; click: boolean; dur: number }[];
};

export function buildModel(steps: Step[]): Model {
  const m: Model = { shots: [], views: [], focuses: [], cursors: [] };
  for (const s of steps) {
    if ("shot" in s) m.shots.push({ at: s.at, name: s.shot, view: s.view });
    else if ("focus" in s) m.focuses.push({ at: s.at, target: s.focus, note: s.note, spot: s.spot ?? true });
    else if ("cursor" in s) m.cursors.push({ at: s.at, target: s.cursor, click: !!s.click, dur: s.dur ?? CURSOR_DUR });
    else if ("view" in s) m.views.push({ at: s.at, view: s.view, dur: s.dur ?? VIEW_DUR });
  }
  for (const k of ["shots", "views", "focuses", "cursors"] as const) (m[k] as { at: number }[]).sort((a, b) => a.at - b.at);
  return m;
}

export const boxOf = (t: Target, shot: ShotInfo | undefined): Box | null => (!shot ? null : typeof t === "string" ? shot.boxes[t] ?? null : t);

export function shotIndexAt(m: Model, t: number): number {
  let i = 0;
  m.shots.forEach((s, k) => {
    if (s.at <= t) i = k;
  });
  return i;
}

/** The camera that a view asks for, on a content area of cw x ch pixels. */
export function viewCam(view: View | undefined, shot: ShotInfo, cw: number, ch: number): Cam {
  const s0 = cw / shot.width;
  const top: Cam = { cx: shot.width / 2, cy: ch / s0 / 2, z: 1 };
  if (!view || view === "top") return top;
  if ("y" in view) return { cx: shot.width / 2, cy: view.y, z: view.zoom ?? 1 };
  const b = boxOf(view.target, shot);
  if (!b) return top;
  const pad = view.pad ?? 40;
  const fit = Math.min(cw / ((b.w + 2 * pad) * s0), ch / ((b.h + 2 * pad) * s0));
  const z = clamp(view.zoom ?? fit, 1, MAX_ZOOM);
  const visH = ch / (s0 * z);
  const cy = view.anchor === "top" || b.h + 2 * pad > visH ? b.y - pad + visH / 2 : b.y + b.h / 2;
  return { cx: b.x + b.w / 2, cy, z };
}

/** Keeps the camera inside the page. */
export function clampCam(c: Cam, shot: ShotInfo, cw: number, ch: number): Cam {
  const S = (cw / shot.width) * c.z;
  const vw = cw / S;
  const vh = ch / S;
  return {
    z: c.z,
    cx: vw >= shot.width ? shot.width / 2 : clamp(c.cx, vw / 2, shot.width - vw / 2),
    cy: vh >= shot.height ? shot.height / 2 : clamp(c.cy, vh / 2, shot.height - vh / 2),
  };
}

/** Camera on shot number i at time t (views between this shot and the next one). */
export function camAt(m: Model, man: Manifest, i: number, t: number, cw: number, ch: number): Cam {
  const s = m.shots[i];
  const shot = man.shots[s.name];
  if (!shot) return { cx: 0, cy: 0, z: 1 };
  const end = m.shots[i + 1]?.at ?? Infinity;
  const keys = [{ at: s.at, cam: viewCam(s.view, shot, cw, ch), dur: 0 }, ...m.views.filter((v) => v.at >= s.at && v.at < end).map((v) => ({ at: v.at, cam: viewCam(v.view, shot, cw, ch), dur: v.dur }))];
  let k = 0;
  keys.forEach((key, n) => {
    if (key.at <= t) k = n;
  });
  const key = keys[k];
  let cam = key.cam;
  if (k > 0 && key.dur > 0 && t < key.at + key.dur) {
    const from = clampCam(keys[k - 1].cam, shot, cw, ch);
    const to = clampCam(key.cam, shot, cw, ch);
    const p = ease(clamp((t - key.at) / key.dur, 0, 1));
    cam = { cx: lerp(from.cx, to.cx, p), cy: lerp(from.cy, to.cy, p), z: Math.exp(lerp(Math.log(from.z), Math.log(to.z), p)) };
  }
  return clampCam(cam, shot, cw, ch);
}

/** Page rectangle → screen rectangle, for a content area at `area` and a camera. */
export function toScreen(b: Box, cam: Cam, shot: ShotInfo, area: Rect): Rect {
  const S = (area.w / shot.width) * cam.z;
  return { x: area.x + area.w / 2 + (b.x - cam.cx) * S, y: area.y + area.h / 2 + (b.y - cam.cy) * S, w: b.w * S, h: b.h * S };
}

export function pageTransform(cam: Cam, shot: ShotInfo, area: Rect) {
  const S = (area.w / shot.width) * cam.z;
  return { S, tx: area.w / 2 - cam.cx * S, ty: area.h / 2 - cam.cy * S };
}

/** The frame on screen at time t: the last focus, until the next focus or the next capture. */
export function focusAt(m: Model, t: number) {
  let f: (Model["focuses"][number] & { until: number }) | null = null;
  m.focuses.forEach((x, n) => {
    if (x.at <= t) {
      const nextFocus = m.focuses[n + 1]?.at ?? Infinity;
      const nextShot = m.shots.find((s) => s.at > x.at)?.at ?? Infinity;
      f = { ...x, until: Math.min(nextFocus, nextShot) };
    }
  });
  return f as (Model["focuses"][number] & { until: number }) | null;
}

/** The notes with their lifetime: each one stays until the next one. */
export function notes(m: Model, sceneDur: number) {
  const list = m.focuses.filter((f) => f.note).map((f) => ({ at: f.at, note: f.note as Note }));
  return list.map((n, k) => ({ ...n, until: list[k + 1]?.at ?? sceneDur }));
}

/** Cursor position (screen) and click state at time t, or null before the first move. */
export function cursorAt(m: Model, man: Manifest, t: number, area: Rect, cw: number, ch: number) {
  if (!m.cursors.length || t < m.cursors[0].at) return null;
  const arrival = (c: Model["cursors"][number]) => {
    const ta = c.at + c.dur;
    const i = shotIndexAt(m, c.at);
    const shot = man.shots[m.shots[i]?.name];
    const b = boxOf(c.target, shot);
    if (!shot || !b) return null;
    const r = toScreen(b, camAt(m, man, i, ta, cw, ch), shot, area);
    return { x: r.x + r.w / 2, y: r.y + r.h / 2, t: ta };
  };
  let prev = { x: area.x + area.w * 0.86, y: area.y + area.h * 1.02 };
  for (let k = 0; k < m.cursors.length; k++) {
    const c = m.cursors[k];
    const a = arrival(c);
    if (!a) continue;
    if (t < c.at) break;
    if (t <= a.t) {
      const p = ease(clamp((t - c.at) / c.dur, 0, 1));
      const mx = (prev.x + a.x) / 2;
      const my = (prev.y + a.y) / 2;
      const dx = a.x - prev.x;
      const dy = a.y - prev.y;
      const bend = 0.16;
      const cx = mx - dy * bend;
      const cy = my + dx * bend;
      const x = (1 - p) * (1 - p) * prev.x + 2 * (1 - p) * p * cx + p * p * a.x;
      const y = (1 - p) * (1 - p) * prev.y + 2 * (1 - p) * p * cy + p * p * a.y;
      return { x, y, click: 0 };
    }
    prev = { x: a.x, y: a.y };
    const since = t - a.t;
    const nextAt = m.cursors[k + 1]?.at ?? Infinity;
    if (t < nextAt) return { x: a.x, y: a.y, click: c.click && since < 0.6 ? since / 0.6 : 0 };
  }
  return { x: prev.x, y: prev.y, click: 0 };
}
