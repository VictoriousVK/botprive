// The vertical cut for TikTok, Reels and Shorts, 1080 x 1920: the phone captures of the product,
// composed for a portrait screen (not a crop of the horizontal film).
import type { Film } from "./types";

const PUSH = { kind: "push", dur: 0.5 } as const;
const SWEEP = { kind: "sweep", dur: 0.6 } as const;

export const VERTICAL: Film = {
  id: "vertical",
  title: "Alpha Edge — format vertical",
  width: 1080,
  height: 1920,
  fps: 30,
  music: "vertical",
  scenes: [
    {
      id: "intro", kind: "intro", short: true, dur: 6, transition: SWEEP,
      captions: [{ at: 3.5, to: 5.8, text: "Le trading, avec des données." }],
      sfx: [{ at: 0.1, name: "riser", gain: 0.6 }, { at: 2.95, name: "impact" }, { at: 3.2, name: "shimmer", gain: 0.7 }],
    },
    {
      id: "problem", kind: "problem", short: true, dur: 6.5, transition: PUSH,
      captions: [{ at: 0.4, to: 6.1, text: "Vos outils, votre plan, votre risque : au même endroit." }],
      sfx: [{ at: 3.6, name: "impact", gain: 0.6 }],
    },
    {
      id: "signup", kind: "tour", device: "phone", dur: 5, transition: PUSH, chapter: { n: "01", kicker: "SIGN UP", title: "Inscription" },
      steps: [
        { at: 0, shot: "m_auth", view: { y: 500, zoom: 1 } },
        { at: 0.2, focus: "next", note: { kicker: "SIGN UP", title: "En deux temps" } },
        { at: 2.4, cursor: "next", click: true },
      ],
      captions: [{ at: 0.3, to: 4.7, text: "Inscription en deux temps, depuis votre téléphone." }],
    },
    {
      id: "firm", kind: "tour", device: "phone", dur: 6, transition: PUSH, chapter: { n: "02", kicker: "PROP FIRM", title: "Votre prop firm" },
      steps: [
        { at: 0, shot: "m_onb_firm", view: { target: "rules", pad: 30, anchor: "top" } },
        { at: 0.2, focus: "rules", note: { kicker: "FIRM RULES", title: "Ses règles, en clair" } },
      ],
      captions: [{ at: 0.3, to: 5.7, text: "Choisissez votre prop firm : ses règles s'affichent en clair." }],
    },
    {
      id: "dashboard", kind: "tour", device: "phone", dur: 9, transition: PUSH, chapter: { n: "03", kicker: "DASHBOARD", title: "Tableau de bord" },
      steps: [
        { at: 0, shot: "m_dashboard", view: { target: "perf", pad: 20, anchor: "top" } },
        { at: 0.2, focus: "perf", note: { kicker: "PERFORMANCE", title: "Calculée sur vos trades" } },
        { at: 3.0, view: { target: "guard", pad: 20, anchor: "top" } },
        { at: 3.2, focus: "guard", note: { kicker: "RISK GUARD", title: "Vos limites, en continu" } },
        { at: 6.0, view: { target: "behaviours", pad: 20, anchor: "top" } },
        { at: 6.2, focus: "behaviours", note: { kicker: "BEHAVIOUR", title: "Vos écarts, repérés" } },
      ],
      captions: [
        { at: 0.3, to: 3.0, text: "Votre performance, calculée sur vos trades." },
        { at: 3.1, to: 5.9, text: "Les limites de la prop firm, en continu." },
        { at: 6.0, to: 8.7, text: "Et vos écarts au plan, repérés." },
      ],
    },
    {
      id: "coach", kind: "tour", device: "phone", dur: 7, transition: PUSH, chapter: { n: "04", kicker: "AI COACH", title: "Coach" },
      steps: [
        { at: 0, shot: "m_coach", view: { target: "verdict", pad: 20, anchor: "top" } },
        { at: 0.2, focus: "verdict", note: { kicker: "AI COACH", title: "Le verdict du Coach" } },
        { at: 2.6, view: { y: 1700 }, dur: 3.2 },
      ],
      captions: [{ at: 0.3, to: 6.7, text: "Le Coach mesure, propose des leçons, et vous décidez." }],
    },
    {
      id: "risk", kind: "tour", device: "phone", dur: 5.5, transition: SWEEP, chapter: { n: "05", kicker: "RISK", title: "Garde-fou" },
      steps: [
        { at: 0, shot: "m_risque", view: { target: "limits", pad: 20, anchor: "top" } },
        { at: 0.2, focus: "limits", note: { kicker: "RISK GUARD", title: "Ce qu'il vous reste" } },
      ],
      captions: [{ at: 0.3, to: 5.2, text: "Ce qu'il vous reste avant chaque limite, à tout moment." }],
    },
    {
      id: "outro", kind: "outro", short: true, dur: 6.5,
      sfx: [{ at: 0.1, name: "impact", gain: 0.8 }, { at: 0.4, name: "shimmer", gain: 0.6 }],
    },
  ],
};
