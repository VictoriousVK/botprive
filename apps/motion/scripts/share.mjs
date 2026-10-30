// A light copy of a rendered film, under a size limit, to send by message or e-mail
// (out/<file>-leger.mp4). Same 1080p picture: the films are mostly still interface, which keeps
// sharper at full resolution with fewer bits than downscaled. Two encoding passes, so the bits go
// where the picture moves.
//   npm run share -- out/alpha-edge-film-1080p.mp4            (28 Mo au plus)
//   npm run share -- out/alpha-edge-promo-1080p.mp4 --max 15
import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const MOTION = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const REMOTION = join(MOTION, "node_modules/@remotion/cli/remotion-cli.js");
const args = process.argv.slice(2);
const maxMiB = Number(args.includes("--max") ? args[args.indexOf("--max") + 1] : 28);
const files = args.filter((a) => a.endsWith(".mp4")).map((f) => resolve(f));
if (!files.length) {
  console.error("usage: node scripts/share.mjs out/<film>.mp4 [--max 28]");
  process.exit(1);
}
const run = (tool, a, capture = false) =>
  execFileSync(process.execPath, [REMOTION, tool, ...a], { cwd: MOTION, encoding: "utf8", stdio: capture ? ["ignore", "pipe", "pipe"] : "inherit" });

for (const file of files) {
  if (!existsSync(file)) {
    console.error(`introuvable : ${file}`);
    process.exit(1);
  }
  const duration = Number(run("ffprobe", ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", file], true));
  const audioK = 96;
  // 3 % kept for the container.
  const videoK = Math.floor(((maxMiB * 1048576 * 8 * 0.97) / duration) / 1000 - audioK);
  if (videoK < 300) {
    console.error(`${file} : ${maxMiB} Mo est trop peu pour ${duration.toFixed(0)} s de vidéo (${videoK} kb/s) ; augmentez --max.`);
    process.exit(1);
  }
  const output = file.replace(/\.mp4$/, "-leger.mp4");
  const log = join(mkdtempSync(join(tmpdir(), "alpha-edge-share-")), "pass");
  const video = ["-c:v", "libx264", "-preset", "slow", "-b:v", `${videoK}k`, "-maxrate", `${videoK * 4}k`, "-bufsize", `${videoK * 8}k`, "-pix_fmt", "yuv420p", "-color_range", "tv", "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709", "-passlogfile", log];
  console.log(`${file} → ${output} (${videoK} kb/s vidéo, ${audioK} kb/s son)`);
  run("ffmpeg", ["-y", "-v", "error", "-i", file, ...video, "-pass", "1", "-an", "-f", "mp4", process.platform === "win32" ? "NUL" : "/dev/null"]);
  run("ffmpeg", ["-y", "-v", "error", "-i", file, ...video, "-pass", "2", "-c:a", "aac", "-b:a", `${audioK}k`, "-movflags", "+faststart", output]);
  rmSync(dirname(log), { recursive: true, force: true });
  console.log(`✓ ${output} : ${(statSync(output).size / 1048576).toFixed(1)} Mo`);
}
