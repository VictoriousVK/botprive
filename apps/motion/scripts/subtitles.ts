// French subtitles (SRT) and the voice-over script, generated from the captions of each film.
//   npm run subtitles   → subtitles/alpha-edge-<film>.fr.srt and VOIX-OFF.fr.md
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { FILM } from "../src/content/film";
import { PROMO } from "../src/content/promo";
import type { Film } from "../src/content/types";
import { VERTICAL } from "../src/content/vertical";
import { captions, place, srtTime } from "../src/lib/timeline";

const MOTION = resolve(dirname(fileURLToPath(import.meta.url)), "..");
/** Comfortable French voice-over pace, in characters per second (spaces included). */
const PACE = 15.5;

const mmss = (s: number) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}.${String(Math.round((s % 1) * 10)).padStart(1, "0")}`;

function srt(film: Film) {
  return captions(film)
    .map((c, i) => `${i + 1}\n${srtTime(c.start)} --> ${srtTime(c.end)}\n${c.text}\n`)
    .join("\n");
}

function script(films: Film[]) {
  const out: string[] = [
    "# Alpha Edge — script de la voix off (français)",
    "",
    "Généré par `npm run subtitles` à partir des sous-titres des films (`src/content/*.ts`) : modifier",
    "le texte là-bas, puis relancer la commande. Les minutages sont ceux du montage.",
    "",
    "**Voix** : française, naturelle, posée ; un débit d'environ 15 caractères par seconde. Aucune",
    "emphase commerciale : le film montre un produit, il ne promet rien. La musique est baissée",
    "automatiquement sous la voix dès que le fichier `public/audio/voice-<film>.wav` existe.",
    "",
    "**Enregistrement** : un fichier WAV par film, calé sur 0:00 du film (silence compris), 44,1 kHz,",
    "pic à -3 dBFS. Nommer `voice-film.wav`, `voice-promo.wav`, `voice-vertical.wav` et les déposer",
    "dans `apps/motion/public/audio/`, puis relancer le rendu.",
    "",
  ];
  for (const film of films) {
    const placed = place(film).scenes;
    out.push(`## ${film.title} (${mmss(place(film).total / film.fps)})`, "");
    for (const p of placed) {
      const caps = p.scene.captions ?? [];
      if (!caps.length) continue;
      const base = p.start / film.fps;
      out.push(`### ${mmss(base)} — ${p.scene.id}`);
      if (p.scene.voice) out.push(`*${p.scene.voice}*`);
      out.push("");
      for (const c of caps) {
        const need = c.text.length / PACE;
        const slot = c.to - c.at;
        const flag = need > slot + 0.3 ? `  ⚠ ${need.toFixed(1)} s de texte pour ${slot.toFixed(1)} s` : "";
        out.push(`- \`${mmss(base + c.at)} → ${mmss(base + c.to)}\` ${c.text}${flag}`);
      }
      out.push("");
    }
  }
  return out.join("\n");
}

/** A scene's lines must end before the next scene starts, or two lines would meet on screen. */
function overlaps(film: Film) {
  const issues: string[] = [];
  const all = captions(film);
  for (const c of all) if (c.end - c.start < 1.2) issues.push(`${film.id}/${c.scene} : « ${c.text} » reste moins de 1,2 s à l'écran`);
  all.forEach((c, i) => {
    if (i && c.start < all[i - 1].end - 1e-6) issues.push(`${film.id} : « ${c.text} » chevauche « ${all[i - 1].text} »`);
  });
  return issues;
}

mkdirSync(join(MOTION, "subtitles"), { recursive: true });
const problems = [FILM, PROMO, VERTICAL].flatMap(overlaps);
if (problems.length) {
  console.error(`Sous-titres qui se chevauchent :\n- ${problems.join("\n- ")}`);
  process.exitCode = 1;
}
for (const film of [FILM, PROMO, VERTICAL]) {
  const file = join(MOTION, "subtitles", `alpha-edge-${film.id}.fr.srt`);
  writeFileSync(file, srt(film));
  console.log(`${file} (${captions(film).length} sous-titres)`);
}
const md = script([FILM, PROMO, VERTICAL]);
writeFileSync(join(MOTION, "VOIX-OFF.fr.md"), md);
const tight = md.split("\n").filter((l) => l.includes("⚠"));
console.log(`VOIX-OFF.fr.md${tight.length ? ` — ${tight.length} ligne(s) serrée(s) :\n${tight.join("\n")}` : " — débit confortable partout"}`);
