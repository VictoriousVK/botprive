// Where each scene starts once transitions overlap, and the cues derived from the films:
// absolute captions (subtitles), sound effects, scene markers for the music. Pure functions,
// shared by the compositions and by the Node scripts (audio, subtitles).
import type { Film, Scene, SfxName } from "../content/types";

export type Placed = { scene: Scene; index: number; start: number; frames: number; transIn: number; transOut: number };

export function place(film: Film): { scenes: Placed[]; total: number } {
  const out: Placed[] = [];
  let t = 0;
  let prevOut = 0;
  film.scenes.forEach((scene, index) => {
    const frames = Math.round(scene.dur * film.fps);
    const last = index === film.scenes.length - 1;
    const transOut = !last && scene.transition ? Math.min(Math.round(scene.transition.dur * film.fps), Math.floor(frames / 2)) : 0;
    out.push({ scene, index, start: t, frames, transIn: prevOut, transOut });
    t += frames - transOut;
    prevOut = transOut;
  });
  const lastScene = out[out.length - 1];
  return { scenes: out, total: lastScene ? lastScene.start + lastScene.frames : 0 };
}

export type AbsCaption = { start: number; end: number; text: string; scene: string };

/** Captions in seconds from the start of the film. A line never runs into the next scene: it is
 *  cut 0.1 s before the next scene starts to come in. */
export function captions(film: Film): AbsCaption[] {
  const { scenes } = place(film);
  return scenes
    .flatMap((p) => {
      const base = p.start / film.fps;
      const limit = base + (p.frames - p.transOut) / film.fps - 0.1;
      return (p.scene.captions ?? []).map((c) => ({ start: base + c.at, end: Math.min(base + c.to, limit), text: c.text, scene: p.scene.id }));
    })
    .sort((a, b) => a.start - b.start);
}

export type Cue = { frame: number; name: SfxName; gain: number };

/** Sound effects: clicks where the cursor lands, typing, transitions, and each scene's own cues. */
export function sfxCues(film: Film): Cue[] {
  const { scenes } = place(film);
  const cues: Cue[] = [];
  const at = (p: Placed, s: number) => p.start + Math.round(s * film.fps);
  for (const p of scenes) {
    const s = p.scene;
    for (const c of s.sfx ?? []) cues.push({ frame: at(p, c.at), name: c.name, gain: c.gain ?? 1 });
    if (s.kind === "tour") {
      for (const st of s.steps) {
        if ("cursor" in st && st.click) cues.push({ frame: at(p, st.at + (st.dur ?? 0.8)), name: "click", gain: 0.9 });
        if ("sfx" in st) cues.push({ frame: at(p, st.at), name: st.sfx, gain: 0.8 });
      }
    }
    if (p.transOut > 0 && s.transition && s.transition.kind !== "fade") cues.push({ frame: p.start + p.frames - p.transOut, name: "whoosh", gain: s.transition.kind === "sweep" ? 0.9 : 0.6 });
  }
  return cues.sort((a, b) => a.frame - b.frame);
}

/** Scene boundaries and their kind, for the music (intensity follows the story). */
export function markers(film: Film) {
  return place(film).scenes.map((p) => ({ id: p.scene.id, kind: p.scene.kind, start: p.start / film.fps, end: (p.start + p.frames) / film.fps }));
}

export const srtTime = (s: number) => {
  const ms = Math.max(0, Math.round(s * 1000));
  const h = Math.floor(ms / 3_600_000);
  const m = Math.floor((ms % 3_600_000) / 60_000);
  const sec = Math.floor((ms % 60_000) / 1000);
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}:${String(sec).padStart(2, "0")},${String(ms % 1000).padStart(3, "0")}`;
};
