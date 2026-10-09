// The captures of the real product (npm run capture): images and the manifest of their zones.
import { useEffect, useState } from "react";
import { continueRender, delayRender, staticFile } from "remotion";
import type { Box } from "../content/types";

export type ShotInfo = { file: string; width: number; height: number; scale: number; full: boolean; url: string; boxes: Record<string, Box> };
export type Manifest = { generated_at: string; shots: Record<string, ShotInfo> };

let cache: Manifest | null | undefined;
let pending: Promise<Manifest | null> | null = null;

const load = () =>
  (pending ??= fetch(staticFile("captures/manifest.json"))
    .then((r) => (r.ok ? (r.json() as Promise<Manifest>) : null))
    .catch(() => null)
    .then((m) => (cache = m)));

/** The manifest, or null when the captures have not been made (npm run capture). */
export function useManifest(): Manifest | null {
  const [m, setM] = useState<Manifest | null>(cache ?? null);
  const [handle] = useState(() => (cache === undefined ? delayRender("captures/manifest.json") : null));
  useEffect(() => {
    if (cache !== undefined) {
      if (handle !== null) continueRender(handle);
      return;
    }
    load().then((v) => {
      setM(v);
      if (handle !== null) continueRender(handle);
    });
  }, [handle]);
  return m;
}

export const shotSrc = (s: ShotInfo) => staticFile(`captures/${s.file}`);
