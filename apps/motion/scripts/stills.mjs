// Renders still frames of a composition, to check scenes without rendering the whole film.
//   node scripts/stills.mjs AlphaEdgeFilm 120 250 900        (frames)
//   node scripts/stills.mjs AlphaEdgeFilm --every 10          (one frame every 10 seconds)
// Output: out/stills/<composition>/<frame>.jpg
import { bundle } from "@remotion/bundler";
import { renderStill, selectComposition } from "@remotion/renderer";
import { mkdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const MOTION = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const [id, ...rest] = process.argv.slice(2);
if (!id) {
  console.error("usage: node scripts/stills.mjs <Composition> <frame...> | --every <seconds>");
  process.exit(1);
}
const browserExecutable = process.env.REMOTION_BROWSER_EXECUTABLE || null;
const serveUrl = await bundle({ entryPoint: join(MOTION, "src/index.ts"), publicDir: join(MOTION, "public") });
const composition = await selectComposition({ serveUrl, id, browserExecutable });
let frames = rest.filter((x) => /^\d+$/.test(x)).map(Number);
const every = rest.indexOf("--every");
if (every >= 0) {
  const step = Math.round(Number(rest[every + 1] || 10) * composition.fps);
  frames = [];
  for (let f = 15; f < composition.durationInFrames; f += step) frames.push(f);
}
const out = join(MOTION, "out/stills", id);
mkdirSync(out, { recursive: true });
for (const frame of frames) {
  const file = join(out, `${String(frame).padStart(5, "0")}.jpg`);
  await renderStill({ composition, serveUrl, frame, output: file, imageFormat: "jpeg", jpegQuality: 88, browserExecutable });
  console.log(`${frame} (${(frame / composition.fps).toFixed(1)} s) → ${file}`);
}
