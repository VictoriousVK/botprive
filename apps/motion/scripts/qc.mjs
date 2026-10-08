// Quality control of the rendered MP4 files: streams, size, duration, frame rate, audio, and one
// frame every few seconds gathered on a contact sheet (out/qc/<file>/index.html) to look at.
//   npm run qc                       (every MP4 in out/)
//   npm run qc -- out/alpha-edge-film-1080p.mp4 --every 5
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, writeFileSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const MOTION = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const every = Number(args.includes("--every") ? args[args.indexOf("--every") + 1] : 8);
const files = args.filter((a) => a.endsWith(".mp4"));
const targets = files.length ? files.map((f) => resolve(f)) : readdirSync(join(MOTION, "out")).filter((f) => f.endsWith(".mp4")).map((f) => join(MOTION, "out", f));
const remotion = join(MOTION, "node_modules/.bin/remotion");
const run = (tool, a) => execFileSync(remotion, [tool, ...a], { cwd: MOTION, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], shell: process.platform === "win32" });

let failures = 0;
for (const file of targets) {
  if (!existsSync(file)) {
    console.error(`introuvable : ${file}`);
    failures++;
    continue;
  }
  const info = JSON.parse(run("ffprobe", ["-v", "error", "-show_streams", "-show_format", "-of", "json", file]));
  const v = info.streams.find((s) => s.codec_type === "video");
  const a = info.streams.find((s) => s.codec_type === "audio");
  const dur = Number(info.format.duration);
  const [num, den] = (v?.r_frame_rate ?? "0/1").split("/").map(Number);
  const fps = num / den;
  const checks = [
    ["vidéo H.264", v?.codec_name === "h264"],
    ["30 images par seconde ou plus", fps >= 29.9],
    ["format 16:9 ou 9:16", v && (Math.abs(v.width / v.height - 16 / 9) < 0.01 || Math.abs(v.height / v.width - 16 / 9) < 0.01)],
    ["piste audio AAC", a?.codec_name === "aac"],
    ["pixels yuv420p (lecture partout)", v?.pix_fmt === "yuv420p"],
  ];
  console.log(`\n${basename(file)} : ${v?.width} x ${v?.height}, ${fps.toFixed(2)} i/s, ${dur.toFixed(1)} s, ${(Number(info.format.size) / 1e6).toFixed(1)} Mo, ${Math.round(Number(info.format.bit_rate) / 1000)} kb/s`);
  for (const [label, ok] of checks) {
    console.log(`  ${ok ? "ok " : "ÉCHEC"} ${label}`);
    if (!ok) failures++;
  }
  // Frames for the contact sheet.
  const dir = join(MOTION, "out/qc", basename(file, ".mp4"));
  mkdirSync(dir, { recursive: true });
  const shots = [];
  for (let t = 1; t < dur; t += every) {
    const out = join(dir, `${String(Math.round(t * 10)).padStart(5, "0")}.jpg`);
    run("ffmpeg", ["-y", "-v", "error", "-ss", String(t), "-i", file, "-frames:v", "1", "-q:v", "3", out]);
    shots.push({ t, file: basename(out) });
  }
  const html = `<!doctype html><meta charset="utf-8"><title>${basename(file)}</title><body style="margin:0;background:#111;color:#ccc;font:13px sans-serif;padding:12px">
<h1 style="font:600 18px sans-serif">${basename(file)} — ${dur.toFixed(1)} s, une image toutes les ${every} s</h1>
<div style="display:grid;grid-template-columns:repeat(${v && v.width > v.height ? 4 : 6},1fr);gap:8px">${shots.map((s) => `<figure style="margin:0"><img src="${s.file}" style="width:100%;display:block"><figcaption>${Math.floor(s.t / 60)}:${String(Math.floor(s.t % 60)).padStart(2, "0")}</figcaption></figure>`).join("")}</div>`;
  writeFileSync(join(dir, "index.html"), html);
  console.log(`  planche : ${join(dir, "index.html")} (${shots.length} images)`);
}
if (failures) {
  console.error(`\n${failures} contrôle(s) en échec`);
  process.exit(1);
}
