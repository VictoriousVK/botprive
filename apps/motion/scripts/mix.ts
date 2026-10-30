// The soundtrack of a film as one WAV file: music, sound effects at their frames, and the voice-over
// when public/audio/voice-<film>.wav exists (music lowered under each line). Same levels as the
// composition's <Soundtrack>; used to assemble films rendered in parts (scripts/render.mjs).
//   npx tsx scripts/mix.ts film out/mix-film.wav
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { FILM } from "../src/content/film";
import { PROMO } from "../src/content/promo";
import type { Film } from "../src/content/types";
import { VERTICAL } from "../src/content/vertical";
import { captions, place, sfxCues } from "../src/lib/timeline";

const MOTION = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const AUDIO = join(MOTION, "public/audio");
const SR = 44100;

type Track = { L: Float32Array; R: Float32Array };

/** Reads a 16-bit PCM WAV (mono or stereo, any rate), resampled to 44.1 kHz. */
function readWav(path: string): Track {
  const b = readFileSync(path);
  let pos = 12;
  let channels = 2;
  let rate = SR;
  let bits = 16;
  let data: Buffer | null = null;
  while (pos + 8 <= b.length) {
    const id = b.toString("ascii", pos, pos + 4);
    const size = b.readUInt32LE(pos + 4);
    if (id === "fmt ") {
      channels = b.readUInt16LE(pos + 10);
      rate = b.readUInt32LE(pos + 12);
      bits = b.readUInt16LE(pos + 22);
    } else if (id === "data") data = b.subarray(pos + 8, pos + 8 + size);
    pos += 8 + size + (size % 2);
  }
  if (!data || bits !== 16) throw new Error(`${path} : WAV PCM 16 bits attendu`);
  const frames = Math.floor(data.length / (2 * channels));
  const n = Math.floor((frames * SR) / rate);
  const L = new Float32Array(n);
  const R = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const src = Math.min(frames - 1, Math.floor((i * rate) / SR));
    const l = data.readInt16LE(src * 2 * channels) / 32768;
    L[i] = l;
    R[i] = channels > 1 ? data.readInt16LE(src * 2 * channels + 2) / 32768 : l;
  }
  return { L, R };
}

function writeWav(path: string, t: Track) {
  const n = t.L.length;
  const buf = Buffer.alloc(44 + n * 4);
  buf.write("RIFF", 0);
  buf.writeUInt32LE(36 + n * 4, 4);
  buf.write("WAVEfmt ", 8);
  buf.writeUInt32LE(16, 16);
  buf.writeUInt16LE(1, 20);
  buf.writeUInt16LE(2, 22);
  buf.writeUInt32LE(SR, 24);
  buf.writeUInt32LE(SR * 4, 28);
  buf.writeUInt16LE(4, 32);
  buf.writeUInt16LE(16, 34);
  buf.write("data", 36);
  buf.writeUInt32LE(n * 4, 40);
  for (let i = 0; i < n; i++) {
    buf.writeInt16LE(Math.round(Math.max(-1, Math.min(1, t.L[i])) * 32767), 44 + i * 4);
    buf.writeInt16LE(Math.round(Math.max(-1, Math.min(1, t.R[i])) * 32767), 46 + i * 4);
  }
  writeFileSync(path, buf);
}

export function mix(film: Film): Track {
  const total = place(film).total / film.fps;
  const n = Math.ceil(total * SR);
  const out: Track = { L: new Float32Array(n), R: new Float32Array(n) };
  const voicePath = join(AUDIO, `voice-${film.id}.wav`);
  const hasVoice = existsSync(voicePath);
  const caps = captions(film);
  // Music level: the same rule as the composition, smoothed over 0.25 s.
  const target = (t: number) => (!hasVoice ? 0.62 : caps.some((c) => t > c.start - 0.35 && t < c.end + 0.35) ? 0.24 : 0.6);
  const musicPath = join(AUDIO, `music-${film.id}.wav`);
  if (existsSync(musicPath)) {
    const m = readWav(musicPath);
    let g = target(0);
    const k = 1 / (0.25 * SR);
    for (let i = 0; i < n && i < m.L.length; i++) {
      g += (target(i / SR) - g) * Math.min(1, k * 4);
      out.L[i] += m.L[i] * g;
      out.R[i] += m.R[i] * g;
    }
  }
  if (hasVoice) {
    const v = readWav(voicePath);
    for (let i = 0; i < n && i < v.L.length; i++) {
      out.L[i] += v.L[i];
      out.R[i] += v.R[i];
    }
  }
  const cache = new Map<string, Track>();
  for (const c of sfxCues(film)) {
    const p = join(AUDIO, "sfx", `${c.name}.wav`);
    if (!existsSync(p)) continue;
    if (!cache.has(p)) cache.set(p, readWav(p));
    const s = cache.get(p) as Track;
    const at = Math.round((c.frame / film.fps) * SR);
    const g = c.gain * (hasVoice ? 0.6 : 0.85);
    for (let i = 0; i < s.L.length && at + i < n; i++) {
      out.L[at + i] += s.L[i] * g;
      out.R[at + i] += s.R[i] * g;
    }
  }
  return out;
}

const FILMS: Record<string, Film> = { film: FILM, promo: PROMO, vertical: VERTICAL };
const [id, target] = process.argv.slice(2);
if (id && target) {
  const film = FILMS[id];
  if (!film) throw new Error(`film inconnu : ${id}`);
  writeWav(resolve(target), mix(film));
  console.log(`bande son de « ${id} » → ${target}`);
}
