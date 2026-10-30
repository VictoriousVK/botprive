// Music and sound effects, synthesised from scratch (no sample, no third-party recording, so no
// rights to clear). The music follows each film's timeline: dark and sparse for the intro, a soft
// electronic pulse during the product tours, a wide final chord for the signature.
//
//   npm run audio            → public/audio/music-film.wav, music-promo.wav, music-vertical.wav, sfx/*.wav
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { FILM } from "../src/content/film";
import { PROMO } from "../src/content/promo";
import type { Film } from "../src/content/types";
import { VERTICAL } from "../src/content/vertical";
import { markers, place } from "../src/lib/timeline";

const SR = 44100;
const OUT = join(resolve(dirname(fileURLToPath(import.meta.url)), ".."), "public/audio");

// ---------------------------------------------------------------- helpers
let seed = 1234567;
const rnd = () => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff) * 2 - 1;
const mtof = (m: number) => 440 * Math.pow(2, (m - 69) / 12);
const clamp = (v: number, a: number, b: number) => Math.min(b, Math.max(a, v));
type Stereo = { L: Float32Array; R: Float32Array };
const stereo = (n: number): Stereo => ({ L: new Float32Array(n), R: new Float32Array(n) });

function writeWav(path: string, s: Stereo) {
  const n = s.L.length;
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
    buf.writeInt16LE(Math.round(clamp(s.L[i], -1, 1) * 32767), 44 + i * 4);
    buf.writeInt16LE(Math.round(clamp(s.R[i], -1, 1) * 32767), 46 + i * 4);
  }
  writeFileSync(path, buf);
}

/** Freeverb (Jezar's public-domain design): 8 combs and 4 allpasses per channel. */
function reverb(input: Stereo, room = 0.84, damp = 0.35, wet = 1): Stereo {
  const n = input.L.length;
  const out = stereo(n);
  const combs = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617];
  const alls = [556, 441, 341, 225];
  const fb = room * 0.28 + 0.7;
  const d1 = damp * 0.4;
  const d2 = 1 - d1;
  for (const [ch, spread] of [["L", 0], ["R", 23]] as const) {
    const dst = out[ch];
    const cb = combs.map((c) => ({ buf: new Float32Array(c + spread), i: 0, store: 0 }));
    const ab = alls.map((a) => ({ buf: new Float32Array(a + spread), i: 0 }));
    for (let k = 0; k < n; k++) {
      const x = (input.L[k] + input.R[k]) * 0.5 * 0.015;
      let acc = 0;
      for (const c of cb) {
        const y = c.buf[c.i];
        c.store = y * d2 + c.store * d1;
        c.buf[c.i] = x + c.store * fb;
        c.i = (c.i + 1) % c.buf.length;
        acc += y;
      }
      for (const a of ab) {
        const b = a.buf[a.i];
        const y = -acc + b;
        a.buf[a.i] = acc + b * 0.5;
        a.i = (a.i + 1) % a.buf.length;
        acc = y;
      }
      dst[k] = acc * wet;
    }
  }
  return out;
}

/** Chamberlin state-variable low-pass, cutoff per sample. */
function lowpass(x: Float32Array, cutoff: (i: number) => number, q = 0.9) {
  let low = 0;
  let band = 0;
  const damp = 1 / q;
  for (let i = 0; i < x.length; i++) {
    const f = 2 * Math.sin((Math.PI * Math.min(cutoff(i), 7000)) / SR);
    low += f * band;
    const high = x[i] - low - damp * band;
    band += f * high;
    x[i] = low;
  }
}

function addInto(dst: Stereo, src: Stereo, at: number, gain = 1, pan = 0) {
  const gl = gain * Math.cos(((pan + 1) * Math.PI) / 4) * Math.SQRT2;
  const gr = gain * Math.sin(((pan + 1) * Math.PI) / 4) * Math.SQRT2;
  for (let i = 0; i < src.L.length; i++) {
    const k = at + i;
    if (k < 0 || k >= dst.L.length) continue;
    dst.L[k] += src.L[i] * gl;
    dst.R[k] += src.R[i] * gr;
  }
}

function master(s: Stereo, peakDb = -1, fadeIn = 0.4, fadeOut = 2.5) {
  const n = s.L.length;
  const drive = 1.25;
  const norm = Math.tanh(drive);
  let peak = 0;
  for (let i = 0; i < n; i++) {
    s.L[i] = Math.tanh(s.L[i] * drive) / norm;
    s.R[i] = Math.tanh(s.R[i] * drive) / norm;
    peak = Math.max(peak, Math.abs(s.L[i]), Math.abs(s.R[i]));
  }
  const g = peak > 0 ? Math.pow(10, peakDb / 20) / peak : 1;
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    const env = Math.min(1, t / fadeIn, (n / SR - t) / fadeOut);
    s.L[i] *= g * Math.max(0, env);
    s.R[i] *= g * Math.max(0, env);
  }
  return s;
}

// ---------------------------------------------------------------- instruments
const CHORDS = [
  { root: 38, notes: [50, 57, 60, 64, 65] }, // D minor 9
  { root: 34, notes: [46, 53, 57, 60, 62] }, // B-flat major 9
  { root: 41, notes: [53, 57, 60, 64, 69] }, // F major 7
  { root: 36, notes: [48, 55, 62, 64, 67] }, // C add 9
];
const CHORD_LEN = 6.4; // seconds
const BEAT = 60 / 96;

/** Pad: three slightly detuned saws per note, filtered; chords cross-fade. */
function pad(n: number, brightness: (t: number) => number, level: (t: number) => number): Stereo {
  const out = stereo(n);
  const phases = new Float64Array(64);
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    const c = Math.floor(t / CHORD_LEN);
    const local = t - c * CHORD_LEN;
    let l = 0;
    let r = 0;
    for (const [k, idx] of [[0, c], [1, c - 1]] as const) {
      if (idx < 0) continue;
      const age = k === 0 ? local : local + CHORD_LEN;
      const env = k === 0 ? Math.min(1, age / 2.2) : Math.max(0, 1 - local / 2.6);
      if (env <= 0) continue;
      const chord = CHORDS[idx % CHORDS.length];
      chord.notes.forEach((m, j) => {
        for (let d = 0; d < 3; d++) {
          const p = (k * 32 + j * 3 + d) % 64;
          const det = (d - 1) * 0.0045;
          phases[p] = (phases[p] + (mtof(m) * (1 + det)) / SR) % 1;
          const v = (phases[p] * 2 - 1) * env * 0.05;
          if (d === 0) l += v;
          else if (d === 2) r += v;
          else {
            l += v * 0.6;
            r += v * 0.6;
          }
        }
      });
    }
    const lv = level(t);
    out.L[i] = l * lv;
    out.R[i] = r * lv;
  }
  lowpass(out.L, (i) => brightness(i / SR));
  lowpass(out.R, (i) => brightness(i / SR) * 1.04);
  return out;
}

function bass(n: number, level: (t: number) => number): Stereo {
  const out = stereo(n);
  let ph = 0;
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    const c = Math.floor(t / CHORD_LEN);
    const local = t - c * CHORD_LEN;
    const f = mtof(CHORDS[c % CHORDS.length].root);
    ph = (ph + f / SR) % 1;
    const env = Math.min(1, local / 0.8) * (0.85 + 0.15 * Math.cos(local * 0.9));
    const v = (Math.sin(ph * 2 * Math.PI) + 0.25 * Math.sin(ph * 4 * Math.PI)) * 0.16 * env * level(t);
    out.L[i] = v;
    out.R[i] = v;
  }
  return out;
}

/** Kick on the beat, ticks on the off-beats, a soft arpeggio: only while `groove(t)` > 0. */
function rhythm(n: number, groove: (t: number) => number): { drums: Stereo; arp: Stereo; duck: Float32Array } {
  const drums = stereo(n);
  const arp = stereo(n);
  const duck = new Float32Array(n).fill(1);
  const total = n / SR;
  for (let b = 0; b * BEAT < total; b++) {
    const t0 = b * BEAT;
    const g = groove(t0);
    if (g <= 0.01) continue;
    // kick
    const k0 = Math.floor(t0 * SR);
    let ph = 0;
    for (let i = 0; i < SR * 0.4 && k0 + i < n; i++) {
      const t = i / SR;
      const f = 45 + 70 * Math.exp(-t * 30);
      ph += f / SR;
      const v = Math.sin(ph * 2 * Math.PI) * Math.exp(-t * 9) * 0.32 * g;
      drums.L[k0 + i] += v;
      drums.R[k0 + i] += v;
      duck[k0 + i] = Math.min(duck[k0 + i], 1 - 0.28 * g * Math.exp(-t * 7));
    }
    // tick on the off-beat
    const h0 = Math.floor((t0 + BEAT / 2) * SR);
    let hp = 0;
    let prev = 0;
    for (let i = 0; i < SR * 0.05 && h0 + i < n; i++) {
      const x = rnd();
      hp = 0.85 * (hp + x - prev);
      prev = x;
      const v = hp * Math.exp((-i / SR) * 90) * 0.05 * g;
      drums.L[h0 + i] += v * 0.8;
      drums.R[h0 + i] += v;
    }
    // arpeggio: two eighths per beat, notes of the current chord, one octave up
    for (let e = 0; e < 2; e++) {
      const ts = t0 + e * (BEAT / 2);
      const chord = CHORDS[Math.floor(ts / CHORD_LEN) % CHORDS.length];
      const step = b * 2 + e;
      const m = chord.notes[[1, 3, 2, 4, 3, 2][step % 6]] + 12;
      const f = mtof(m);
      const a0 = Math.floor(ts * SR);
      const pan = step % 2 ? 0.35 : -0.35;
      for (let i = 0; i < SR * 0.6 && a0 + i < n; i++) {
        const t = i / SR;
        const env = Math.min(1, t / 0.004) * Math.exp(-t * 6.5);
        const v = (Math.sin(2 * Math.PI * f * t) + 0.3 * Math.sin(4 * Math.PI * f * t) + 0.12 * Math.sin(6 * Math.PI * f * t)) * env * 0.045 * g;
        arp.L[a0 + i] += v * (1 - pan);
        arp.R[a0 + i] += v * (1 + pan);
      }
    }
  }
  return { drums, arp, duck };
}

// ---------------------------------------------------------------- the score of a film
function music(film: Film) {
  const dur = place(film).total / film.fps;
  const n = Math.ceil(dur * SR) + SR;
  const marks = markers(film);
  const kindAt = (t: number) => {
    let k = marks[0]?.kind ?? "intro";
    for (const m of marks) if (t >= m.start) k = m.kind;
    return k;
  };
  const sceneAt = (t: number) => marks.reduce((cur, m) => (t >= m.start ? m : cur), marks[0]);
  const intro = marks.find((m) => m.kind === "intro");
  const introEnd = intro ? intro.start + (film.music === "film" ? 7.55 : 2.95) : 0;
  const outro = marks.find((m) => m.kind === "outro");

  const brightness = (t: number) => {
    if (t < introEnd) return 380 + (t / introEnd) * 900;
    const k = kindAt(t);
    if (k === "outro") return 2600;
    if (k === "problem") return 1100 + 300 * Math.sin(t * 0.3);
    if (k === "fvg") return 1300;
    return 1900 + 300 * Math.sin(t * 0.15);
  };
  // Dynamics: the intro rises from almost nothing to the flare; the teaching scene is calmer;
  // the tours sit a little lower (the pulse carries them); the signature opens up.
  const padLevel = (t: number) => {
    if (t < introEnd) return 0.25 + 0.75 * Math.pow(t / introEnd, 2);
    const k = kindAt(t);
    return k === "fvg" ? 0.7 : k === "tour" || k === "alert" ? 0.78 : k === "chapter" ? 0.95 : k === "problem" ? 0.85 : 1;
  };
  const groove = (t: number) => {
    const k = kindAt(t);
    const s = sceneAt(t);
    if (k === "intro" || k === "outro" || k === "chapter" || k === "fvg") return 0;
    const into = clamp((t - s.start) / 1.5, 0, 1);
    const left = clamp((s.end - t) / 0.8, 0, 1);
    const base = k === "problem" ? 0.55 : 1;
    return base * Math.min(into, left);
  };

  const p = pad(n, brightness, padLevel);
  const b = bass(n, (t) => (t < introEnd - 2 ? 0.6 : kindAt(t) === "problem" ? 0.8 : 1));
  const { drums, arp, duck } = rhythm(n, groove);
  for (let i = 0; i < n; i++) {
    p.L[i] *= duck[i];
    p.R[i] *= duck[i];
  }
  const send = stereo(n);
  addInto(send, p, 0, 0.9);
  addInto(send, arp, 0, 1.4);
  const wet = reverb(send, 0.88, 0.3);

  const mix = stereo(n);
  addInto(mix, p, 0, 1);
  addInto(mix, b, 0, 1);
  addInto(mix, drums, 0, 1);
  addInto(mix, arp, 0, 0.9);
  addInto(mix, wet, 0, 0.75);
  // the final chord rings out under the signature
  if (outro) {
    const o0 = Math.floor(outro.start * SR);
    for (let i = o0; i < n; i++) {
      const t = (i - o0) / SR;
      const swell = Math.min(1, t / 3) * 0.25;
      mix.L[i] *= 1 + swell;
      mix.R[i] *= 1 + swell;
    }
  }
  return master(mix, -1.5, 0.3, Math.min(3, dur * 0.1));
}

// ---------------------------------------------------------------- sound effects
function fx(len: number, fn: (t: number, i: number) => [number, number]): Stereo {
  const n = Math.floor(len * SR);
  const s = stereo(n);
  for (let i = 0; i < n; i++) {
    const [l, r] = fn(i / SR, i);
    s.L[i] = l;
    s.R[i] = r;
  }
  return s;
}

function withReverb(s: Stereo, amount: number, tail = 1.5): Stereo {
  const n = s.L.length + Math.floor(tail * SR);
  const dry = stereo(n);
  addInto(dry, s, 0, 1);
  const wet = reverb(dry, 0.86, 0.35);
  addInto(dry, wet, 0, amount);
  return dry;
}

function sfxSet(): Record<string, Stereo> {
  const noise = () => rnd();
  const click = fx(0.12, (t) => {
    const v = (Math.sin(2 * Math.PI * 2100 * t) * Math.exp(-t * 90) * 0.5 + noise() * Math.exp(-t * 400) * 0.35) * 0.8;
    return [v, v];
  });
  const tick = fx(0.12, (t) => {
    const v = Math.sin(2 * Math.PI * 1250 * t) * Math.exp(-t * 60) * 0.5;
    return [v, v];
  });
  // whoosh: band-passed noise sweeping up then down, travelling left to right
  let lo = 0;
  let bd = 0;
  const whoosh = fx(0.9, (t) => {
    const p = t / 0.9;
    const fc = 300 + 2600 * Math.sin(Math.PI * p);
    const f = 2 * Math.sin((Math.PI * fc) / SR);
    lo += f * bd;
    const hi = noise() - lo - 0.7 * bd;
    bd += f * hi;
    const v = bd * Math.sin(Math.PI * p) ** 1.5 * 0.5;
    return [v * (1 - p), v * p];
  });
  let ip = 0;
  const impact = withReverb(
    fx(1.8, (t) => {
      ip += (38 + 30 * Math.exp(-t * 5)) / SR;
      const v = Math.sin(ip * 2 * Math.PI) * Math.exp(-t * 2.4) * 0.9 + noise() * Math.exp(-t * 25) * 0.25;
      return [v, v];
    }),
    0.6,
    2.5,
  );
  const shimmer = withReverb(
    fx(2.6, (t) => {
      const env = Math.min(1, t / 0.4) * Math.exp(-t * 1.4);
      const notes = [86, 93, 100, 102].map(mtof);
      const l = notes.reduce((a, f, k) => a + Math.sin(2 * Math.PI * f * t + k) * (k % 2 ? 0.5 : 1), 0) * env * 0.07 * (1 + 0.3 * Math.sin(t * 22));
      const r = notes.reduce((a, f, k) => a + Math.sin(2 * Math.PI * f * 1.002 * t + k) * (k % 2 ? 1 : 0.5), 0) * env * 0.07 * (1 + 0.3 * Math.sin(t * 19));
      return [l, r];
    }),
    0.9,
    2.5,
  );
  const keys = [0, 0.09, 0.17, 0.29, 0.36, 0.47, 0.55, 0.66, 0.74, 0.86];
  const type = fx(1.0, (t) => {
    let v = 0;
    for (const k of keys) {
      const d = t - k;
      if (d >= 0 && d < 0.04) v += (noise() * 0.5 + Math.sin(2 * Math.PI * 1600 * d) * 0.4) * Math.exp(-d * 160) * 0.35;
    }
    return [v, v];
  });
  const success = withReverb(
    fx(1.0, (t) => {
      const a = t < 0.5 ? Math.sin(2 * Math.PI * mtof(81) * t) * Math.exp(-t * 8) : 0;
      const d = t - 0.11;
      const b2 = d > 0 ? Math.sin(2 * Math.PI * mtof(86) * d) * Math.exp(-d * 6) : 0;
      const v = (a + b2) * 0.22;
      return [v, v];
    }),
    0.5,
    1.2,
  );
  const notify = withReverb(
    fx(1.2, (t) => {
      const a = Math.sin(2 * Math.PI * mtof(88) * t) * Math.exp(-t * 7);
      const d = t - 0.16;
      const b2 = d > 0 ? Math.sin(2 * Math.PI * mtof(95) * d) * Math.exp(-d * 5) : 0;
      const v = (a + b2) * 0.2;
      return [v, v];
    }),
    0.5,
    1.2,
  );
  let rl = 0;
  let rb = 0;
  const riser = fx(2.2, (t) => {
    const p = t / 2.2;
    const fc = 250 + 5200 * p * p;
    const f = 2 * Math.sin((Math.PI * Math.min(fc, 6500)) / SR);
    rl += f * rb;
    const hi = noise() - rl - 0.5 * rb;
    rb += f * hi;
    const tone = Math.sin(2 * Math.PI * (200 + 600 * p * p) * t) * 0.08;
    const v = (rb * 0.45 + tone) * p * p;
    return [v, v * 0.95];
  });
  return { click, tick, whoosh, impact, shimmer, type, success, notify, riser };
}

// ---------------------------------------------------------------- main
mkdirSync(join(OUT, "sfx"), { recursive: true });
const wanted = process.argv.slice(2);
for (const film of [FILM, PROMO, VERTICAL]) {
  if (wanted.length && !wanted.includes(film.id)) continue;
  const t0 = Date.now();
  writeWav(join(OUT, `music-${film.id}.wav`), music(film));
  console.log(`music-${film.id}.wav  (${((place(film).total / film.fps)).toFixed(1)} s, ${((Date.now() - t0) / 1000).toFixed(1)} s de calcul)`);
}
// Peak level of each effect: transients stay under the music, accents above it.
const LEVEL: Record<string, number> = { click: -11, tick: -14, type: -15, whoosh: -9, impact: -5, shimmer: -9, success: -11, notify: -9, riser: -9 };
for (const [name, s] of Object.entries(sfxSet())) writeWav(join(OUT, "sfx", `${name}.wav`), master(s, LEVEL[name] ?? -9, 0.001, 0.05));
console.log("sfx : click, tick, whoosh, impact, shimmer, type, success, notify, riser");
