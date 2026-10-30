// Times the rendering of a few frames of each kind of scene (to find what is slow).
//   node scripts/bench.mjs AlphaEdgeFilm 60-89 1300-1329
import { bundle } from "@remotion/bundler";
import { renderMedia, selectComposition } from "@remotion/renderer";
import { cpus, tmpdir } from "node:os";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const MOTION = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const [id, ...ranges] = process.argv.slice(2);
const browserExecutable = process.env.REMOTION_BROWSER_EXECUTABLE || null;
const serveUrl = await bundle({ entryPoint: join(MOTION, "src/index.ts"), publicDir: join(MOTION, "public") });
const composition = await selectComposition({ serveUrl, id, browserExecutable, inputProps: JSON.parse(process.env.PROPS || "{}") });
for (const r of ranges) {
  const [a, b] = r.split("-").map(Number);
  const t0 = Date.now();
  await renderMedia({ composition, serveUrl, codec: "h264", muted: true, frameRange: [a, b], outputLocation: join(tmpdir(), `bench-${a}.mp4`), browserExecutable,
    concurrency: Number(process.env.CONC || cpus().length), imageFormat: "jpeg", chromiumOptions: { gl: process.env.GL || "swangle" }, inputProps: JSON.parse(process.env.PROPS || "{}") });
  const s = (Date.now() - t0) / 1000;
  console.log(`${r}: ${(b - a + 1)} images en ${s.toFixed(1)} s → ${((b - a + 1) / s).toFixed(2)} images/s`);
}
