// Renders the films to MP4 (H.264, AAC), 30 fps.
//   npm run render:film        → out/alpha-edge-film-1080p.mp4        (about 4 min 50)
//   npm run render:promo       → out/alpha-edge-promo-1080p.mp4       (about 45 s)
//   npm run render:vertical    → out/alpha-edge-vertical-1080x1920.mp4 (about 48 s)
//   npm run render:all
// Options (after --): --clean (no burnt-in captions), --4k (film and promo at 3840 x 2160),
//                     --concurrency N, --frames 0-299 (a range, to test),
//                     --segments 1800 (render in parts of N frames, resumable: parts already in
//                     out/parts are kept; then the parts are joined without re-encoding and the
//                     full soundtrack is added), --max-parts K (stop after K new parts).
import { bundle } from "@remotion/bundler";
import { renderMedia, selectComposition } from "@remotion/renderer";
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, renameSync, statSync, writeFileSync } from "node:fs";
import { cpus } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const MOTION = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const basenameOf = (f) => f.split(/[\\/]/).pop().replace(/\.mp4$/, "");
const args = process.argv.slice(2);
const flag = (k) => args.includes(k);
const opt = (k) => (args.includes(k) ? args[args.indexOf(k) + 1] : undefined);
const FILMS = {
  film: { id: "AlphaEdgeFilm", file: "alpha-edge-film" },
  promo: { id: "AlphaEdgePromo", file: "alpha-edge-promo" },
  vertical: { id: "AlphaEdgeVertical", file: "alpha-edge-vertical" },
};
const wanted = args.filter((a) => a in FILMS);
if (!wanted.length) {
  console.error("usage: node scripts/render.mjs film|promo|vertical [...] [--clean] [--4k] [--concurrency N] [--frames A-B]");
  process.exit(1);
}

// What the films need before rendering.
if (!existsSync(join(MOTION, "public/captures/manifest.json"))) {
  console.error("Captures du produit absentes : lancez d'abord « npm run capture » (le serveur de démonstration doit pouvoir démarrer).");
  process.exit(1);
}
// Node runs the tools directly (no shell): works on Windows, macOS and Linux, spaces in paths included.
const TSX = join(MOTION, "node_modules/tsx/dist/cli.mjs");
const REMOTION = join(MOTION, "node_modules/@remotion/cli/remotion-cli.js");
const tool = (cli, a) => execFileSync(process.execPath, [cli, ...a], { stdio: "inherit", cwd: MOTION });
if (!existsSync(join(MOTION, "public/audio/music-film.wav"))) {
  console.log("Musique absente : génération (npm run audio)…");
  tool(TSX, [join(MOTION, "scripts/audio.ts")]);
}
tool(TSX, [join(MOTION, "scripts/subtitles.ts")]);

const browserExecutable = process.env.REMOTION_BROWSER_EXECUTABLE || null;
console.log("Préparation du projet (bundle)…");
const serveUrl = await bundle({ entryPoint: join(MOTION, "src/index.ts"), publicDir: join(MOTION, "public") });
mkdirSync(join(MOTION, "out"), { recursive: true });

for (const key of wanted) {
  const f = FILMS[key];
  const id = flag("--clean") ? `${f.id}Clean` : f.id;
  const composition = await selectComposition({ serveUrl, id, browserExecutable });
  const big = flag("--4k") && key !== "vertical";
  const size = key === "vertical" ? "1080x1920" : big ? "2160p" : "1080p";
  const output = join(MOTION, "out", `${f.file}${flag("--clean") ? "-sans-sous-titres" : ""}-${size}.mp4`);
  const range = opt("--frames")?.split("-").map(Number);
  const started = Date.now();
  const common = { composition, serveUrl, browserExecutable, chromiumOptions: { gl: "swangle" }, concurrency: Number(opt("--concurrency") ?? Math.max(1, cpus().length - 1)) };
  const segSize = Number(opt("--segments") ?? 0);
  if (segSize > 0) {
    // Resumable rendering in parts (video only), then join and add the whole soundtrack.
    const partsDir = join(MOTION, "out/parts", basenameOf(output));
    mkdirSync(partsDir, { recursive: true });
    const total = composition.durationInFrames;
    const parts = [];
    let made = 0;
    const maxParts = Number(opt("--max-parts") ?? Infinity);
    for (let a = 0, k = 0; a < total; a += segSize, k++) {
      const b = Math.min(total - 1, a + segSize - 1);
      const file = join(partsDir, `part-${String(k).padStart(3, "0")}.mp4`);
      parts.push(file);
      if (existsSync(file)) continue;
      if (made >= maxParts) continue;
      const t0 = Date.now();
      let lastPct = -1;
      await renderMedia({
        ...common, codec: "h264", crf: big ? 20 : 18, pixelFormat: "yuv420p", imageFormat: "jpeg", jpegQuality: 92, scale: big ? 2 : 1, muted: true,
        frameRange: [a, b], outputLocation: file + ".tmp.mp4",
        onProgress: ({ progress }) => {
          const pct = Math.floor(progress * 10) * 10;
          if (pct !== lastPct) {
            lastPct = pct;
            console.log(`${key} partie ${k + 1} (images ${a}-${b}) ${pct} %, ${Math.round((Date.now() - t0) / 1000)} s`);
          }
        },
      });
      renameSync(file + ".tmp.mp4", file);
      made++;
      console.log(`  partie ${k + 1} prête : ${((b - a + 1) / ((Date.now() - t0) / 1000)).toFixed(2)} images/s`);
    }
    const missing = parts.filter((f) => !existsSync(f)).length;
    if (missing) {
      console.log(`\n${missing} partie(s) restante(s) : relancez la même commande pour continuer.`);
      continue;
    }
    const audio = join(partsDir, "soundtrack.wav");
    console.log("Piste audio complète…");
    await renderMedia({ ...common, codec: "wav", outputLocation: audio });
    const list = join(partsDir, "parts.txt");
    writeFileSync(list, parts.map((f) => `file '${f.replace(/'/g, "'\\''")}'`).join("\n"));
    const joined = join(partsDir, "video.mp4");
    tool(REMOTION, ["ffmpeg", "-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", list, "-c", "copy", joined]);
    tool(REMOTION, ["ffmpeg", "-y", "-v", "error", "-i", joined, "-i", audio, "-map", "0:v:0", "-map", "1:a:0", "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-shortest", "-movflags", "+faststart", output]);
    console.log(`\n✓ ${output}\n  ${(statSync(output).size / 1e6).toFixed(1)} Mo\n`);
    continue;
  }
  let last = -1;
  await renderMedia({
    composition,
    serveUrl,
    codec: "h264",
    crf: big ? 20 : 18,
    pixelFormat: "yuv420p",
    audioCodec: "aac",
    audioBitrate: "192k",
    imageFormat: "jpeg",
    jpegQuality: 92,
    scale: big ? 2 : 1,
    outputLocation: output,
    concurrency: Number(opt("--concurrency") ?? Math.max(1, cpus().length - 1)),
    frameRange: range && range.length === 2 ? [range[0], range[1]] : null,
    browserExecutable,
    chromiumOptions: { gl: "swangle" },
    onProgress: ({ progress, renderedFrames, encodedFrames }) => {
      const pct = Math.floor(progress * 100);
      if (pct !== last && pct % 5 === 0) {
        last = pct;
        const s = (Date.now() - started) / 1000;
        console.log(`${key} ${String(pct).padStart(3)} %  (${renderedFrames} images rendues, ${encodedFrames} encodées, ${Math.round(s)} s)`);
      }
    },
  });
  const mb = statSync(output).size / 1e6;
  console.log(`\n✓ ${output}\n  ${composition.width} x ${composition.height} × ${big ? 2 : 1}, ${composition.fps} i/s, ${(composition.durationInFrames / composition.fps).toFixed(1)} s, ${mb.toFixed(1)} Mo, ${Math.round((Date.now() - started) / 1000)} s de rendu\n`);
}
