// The film's look: black, gold, white, grey. Every colour, font and easing is set here.
import { Easing } from "remotion";

export const C = {
  black: "#050506",
  ink: "#0A0B0E",
  panel: "#0F1116",
  panelHi: "#161922",
  hair: "rgba(212, 179, 116, 0.30)",
  hairSoft: "rgba(212, 179, 116, 0.14)",
  gold: "#D4B374",
  goldLight: "#EAD6A6",
  goldDeep: "#9C7838",
  white: "#F5F2EA",
  grey: "#A2A7AF",
  dim: "#62676F",
  faint: "#30333A",
  up: "#4BE08A",
  down: "#EF5354",
  blue: "#4FB0FF",
} as const;

export const F = {
  display: "Montserrat, 'Inter Variable', sans-serif",
  body: "'Inter Variable', Inter, sans-serif",
  mono: "'JetBrains Mono', ui-monospace, monospace",
} as const;

export const EASE = {
  cine: Easing.bezier(0.65, 0, 0.35, 1), // camera moves
  out: Easing.bezier(0.22, 1, 0.36, 1), // entrances
  in: Easing.bezier(0.55, 0, 1, 0.45), // exits
  soft: Easing.bezier(0.4, 0, 0.2, 1),
};

export const goldGradient = `linear-gradient(100deg, ${C.goldDeep} 0%, ${C.goldLight} 38%, #FFF4DA 50%, ${C.goldLight} 62%, ${C.goldDeep} 100%)`;
