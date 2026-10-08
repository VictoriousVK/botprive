// The short promotional cut, 1920 x 1080, about 40 seconds: the same scenes, faster.
import type { Film } from "./types";

const SWEEP = { kind: "sweep", dur: 0.6 } as const;
const PUSH = { kind: "push", dur: 0.5 } as const;

export const PROMO: Film = {
  id: "promo",
  title: "Alpha Edge — film court",
  width: 1920,
  height: 1080,
  fps: 30,
  music: "promo",
  scenes: [
    {
      id: "intro", kind: "intro", short: true, dur: 7, transition: SWEEP,
      captions: [{ at: 3.9, to: 6.7, text: "Alpha Edge. Le trading, avec des données." }],
      sfx: [{ at: 0.1, name: "riser", gain: 0.6 }, { at: 2.95, name: "impact" }, { at: 3.2, name: "shimmer", gain: 0.7 }],
    },
    {
      id: "problem", kind: "problem", short: true, dur: 6.5, transition: PUSH,
      captions: [{ at: 0.4, to: 6.0, text: "Vos outils, votre plan, votre risque : enfin au même endroit." }],
      sfx: [{ at: 3.6, name: "impact", gain: 0.6 }],
    },
    {
      id: "dashboard", kind: "tour", dur: 6.5, transition: PUSH, chapter: { n: "01", kicker: "THE DASHBOARD", title: "Tableau de bord" },
      steps: [
        { at: 0, shot: "dashboard", view: { target: "perf", pad: 36 } },
        { at: 0.2, focus: "perf", note: { kicker: "PERFORMANCE", title: "Calculée sur vos trades" } },
        { at: 3.2, view: { target: "behaviours", pad: 36 } },
        { at: 3.4, focus: "behaviours", note: { kicker: "BEHAVIOUR", title: "Vos écarts, repérés" } },
      ],
      captions: [{ at: 0.3, to: 6.0, text: "Un tableau de bord calculé sur vos trades." }],
    },
    {
      id: "coach", kind: "tour", dur: 6, transition: PUSH, chapter: { n: "02", kicker: "AI COACH", title: "Coach" },
      steps: [
        { at: 0, shot: "coach_verdict", view: { target: "measures", pad: 40 } },
        { at: 0.2, focus: "measures", note: { kicker: "AI COACH", title: "Écarts au plan, mesurés" } },
        { at: 3.0, view: { target: "lessons", pad: 40 } },
        { at: 3.2, focus: "lessons", note: { kicker: "LESSONS", title: "Leçons que vous validez" } },
      ],
      captions: [{ at: 0.3, to: 5.6, text: "Un Coach qui mesure vos écarts au plan." }],
    },
    {
      id: "risk", kind: "tour", dur: 5.5, transition: PUSH, chapter: { n: "03", kicker: "RISK GUARD", title: "Garde-fou" },
      steps: [
        { at: 0, shot: "risque_topstep", view: { target: "calc", pad: 30, anchor: "top" } },
        { at: 0.2, focus: "resultBlock", note: { kicker: "PROP FIRM", title: "Le risque en contrats" } },
      ],
      captions: [{ at: 0.3, to: 5.1, text: "Un garde-fou aux règles de votre prop firm." }],
    },
    {
      id: "analyse", kind: "tour", dur: 5, transition: PUSH, chapter: { n: "04", kicker: "ICT ANALYSIS", title: "Analyse ICT" }, tag: "Prix simulés · démonstration",
      steps: [
        { at: 0, shot: "analyse_card", view: { target: "chart", pad: 30 } },
        { at: 0.2, focus: "chart", note: { kicker: "ICT", title: "Liquidité, FVG, niveaux" } },
      ],
      captions: [{ at: 0.3, to: 4.6, text: "Une analyse ICT aux règles écrites." }],
    },
    {
      id: "console", kind: "tour", dur: 5, transition: SWEEP, chapter: { n: "05", kicker: "EA · BACKTEST", title: "Robots" },
      steps: [
        { at: 0, shot: "console_backtest", view: "top" },
        { at: 0.2, focus: "dialog", note: { kicker: "BACKTEST", title: "Tester avant le réel" } },
      ],
      captions: [{ at: 0.3, to: 4.6, text: "Des robots testés avant le réel, sous trois verrous." }],
    },
    {
      id: "outro", kind: "outro", short: true, dur: 6.5,
      sfx: [{ at: 0.1, name: "impact", gain: 0.8 }, { at: 0.4, name: "shimmer", gain: 0.6 }],
    },
  ],
};
