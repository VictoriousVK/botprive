// The films are described as data: scenes, durations, captions, camera moves, clicks. Editing a
// film means editing src/content/*.ts; the components only render what is described here.
// Times are in seconds, relative to the start of their scene.

/** A rectangle on a captured page, in CSS pixels of that page. */
export type Box = { x: number; y: number; w: number; h: number };
/** A named zone from public/captures/manifest.json (e.g. "perf"), or an explicit rectangle. */
export type Target = string | Box;

/** Where the camera looks on the current capture. */
export type View =
  | "top"
  | { y: number; zoom?: number }
  | { target: Target; pad?: number; zoom?: number; anchor?: "center" | "top" };

export type Caption = { at: number; to: number; text: string };
export type Note = { kicker: string; title: string; text?: string };
export type SfxName = "click" | "whoosh" | "impact" | "shimmer" | "type" | "success" | "tick" | "riser" | "notify";

export type Step =
  /** Shows a capture (cross-dissolve from the previous one). */
  | { at: number; shot: string; view?: View }
  /** Moves the camera (default 1.1 s). */
  | { at: number; view: View; dur?: number }
  /** Frames a zone; the note appears beside the screen until the next note. */
  | { at: number; focus: Target; note?: Note; spot?: boolean }
  /** Moves the cursor to a zone (default 0.8 s) and clicks on arrival. */
  | { at: number; cursor: Target; click?: boolean; dur?: number }
  | { at: number; sfx: SfxName };

export type TransitionKind = "fade" | "sweep" | "push" | "dip";
export type Transition = { kind: TransitionKind; dur: number };

type Base = {
  id: string;
  dur: number;
  captions?: Caption[];
  /** Transition into the next scene. */
  transition?: Transition;
  sfx?: { at: number; name: SfxName; gain?: number }[];
  /** Direction for the voice-over (tone, pace). */
  voice?: string;
};

export type Chapter = { n: string; kicker: string; title: string };

export type Scene =
  | (Base & { kind: "intro"; short?: boolean })
  | (Base & { kind: "problem"; short?: boolean })
  | (Base & { kind: "chapter"; chapter: Chapter })
  | (Base & { kind: "tour"; chapter: Chapter; device?: "window" | "phone"; steps: Step[]; tag?: string })
  | (Base & { kind: "fvg" })
  | (Base & { kind: "alert" })
  | (Base & { kind: "outro"; short?: boolean });

export type Film = {
  id: string;
  title: string;
  width: number;
  height: number;
  fps: number;
  /** Music character for scripts/audio.ts. */
  music: "film" | "promo" | "vertical";
  scenes: Scene[];
};
