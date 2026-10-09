// Any film of src/content: its scenes in sequence with their transitions, the captions, the music,
// the sound effects and (when present) the voice-over.
import { AbsoluteFill, Audio, getStaticFiles, interpolate, Sequence, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { Captions } from "../components/Captions";
import type { Film, Scene, TransitionKind } from "../content/types";
import { captions, place, sfxCues, type Placed } from "../lib/timeline";
import { ease } from "../lib/tour";
import { AlertScene } from "../scenes/Alert";
import { ChapterScene } from "../scenes/Chapter";
import { FvgScene } from "../scenes/Fvg";
import { IntroScene } from "../scenes/Intro";
import { OutroScene } from "../scenes/Outro";
import { ProblemScene } from "../scenes/Problem";
import { TourScene } from "../scenes/Tour";
import { C } from "../theme";

const clamp01 = (v: number) => Math.min(1, Math.max(0, v));

const SceneView: React.FC<{ scene: Scene }> = ({ scene }) => {
  switch (scene.kind) {
    case "intro":
      return <IntroScene short={scene.short} />;
    case "problem":
      return <ProblemScene short={scene.short} />;
    case "chapter":
      return <ChapterScene chapter={scene.chapter} />;
    case "tour":
      return <TourScene steps={scene.steps} dur={scene.dur} chapter={scene.chapter} device={scene.device} tag={scene.tag} />;
    case "fvg":
      return <FvgScene />;
    case "alert":
      return <AlertScene />;
    case "outro":
      return <OutroScene short={scene.short} />;
  }
};

/** Entering and leaving effects; the next scene is drawn on top of the previous one. */
const Shell: React.FC<{ p: Placed; inKind?: TransitionKind; children: React.ReactNode }> = ({ p, inKind, children }) => {
  const frame = useCurrentFrame();
  const { width, height } = useVideoConfig();
  const pe = p.transIn ? ease(clamp01(frame / p.transIn)) : 1;
  const px = p.transOut ? ease(clamp01((frame - (p.frames - p.transOut)) / p.transOut)) : 0;
  const outKind = p.scene.transition?.kind;
  let opacity = 1;
  let scale = 1;
  let clip: string | undefined;
  let bar: React.ReactNode = null;
  if (p.transIn && pe < 1) {
    if (inKind === "fade") opacity *= pe;
    if (inKind === "push") {
      opacity *= pe;
      scale *= 0.94 + 0.06 * pe;
    }
    if (inKind === "dip") opacity *= pe * pe;
    if (inKind === "sweep") {
      const skew = width * 0.22;
      const xt = -skew + pe * (width + skew * 2);
      const xb = xt - skew;
      clip = `polygon(0 0, ${xt}px 0, ${xb}px ${height}px, 0 ${height}px)`;
      const angle = (Math.atan2(skew, height) * 180) / Math.PI;
      bar = (
        <div
          style={{
            position: "absolute",
            left: (xt + xb) / 2 - 90,
            top: -height * 0.2,
            width: 180,
            height: height * 1.4,
            transform: `rotate(${angle}deg)`,
            background: `linear-gradient(90deg, transparent, rgba(212,179,116,0.35) 35%, rgba(255,248,230,0.9) 50%, rgba(212,179,116,0.35) 65%, transparent)`,
            mixBlendMode: "screen",
            opacity: Math.sin(pe * Math.PI),
          }}
        />
      );
    }
  }
  if (p.transOut && px > 0) {
    if (outKind === "push") {
      scale *= 1 + 0.05 * px;
      opacity *= 1 - 0.9 * px;
    }
    if (outKind === "dip") opacity *= 1 - px;
    if (outKind === "sweep") scale *= 1 + 0.025 * px;
  }
  return (
    <AbsoluteFill>
      <AbsoluteFill style={{ opacity, transform: scale !== 1 ? `scale(${scale})` : undefined, clipPath: clip }}>{children}</AbsoluteFill>
      {bar}
    </AbsoluteFill>
  );
};

const Soundtrack: React.FC<{ film: Film }> = ({ film }) => {
  const { fps } = useVideoConfig();
  const files = new Set(getStaticFiles().map((f) => f.name));
  const music = `audio/music-${film.id}.wav`;
  const voice = `audio/voice-${film.id}.wav`;
  const hasVoice = files.has(voice);
  const caps = captions(film);
  const cues = sfxCues(film);
  // Music under the voice: lowered while a line is spoken (only when a voice-over track exists).
  const musicVolume = (f: number) => {
    const t = f / fps;
    if (!hasVoice) return 0.62;
    const near = caps.some((c) => t > c.start - 0.35 && t < c.end + 0.35);
    return near ? 0.24 : 0.6;
  };
  return (
    <>
      {files.has(music) && <Audio src={staticFile(music)} volume={musicVolume} />}
      {hasVoice && <Audio src={staticFile(voice)} />}
      {cues.map((c, i) =>
        files.has(`audio/sfx/${c.name}.wav`) ? (
          <Sequence key={i} from={c.frame} durationInFrames={fps * 4} layout="none">
            <Audio src={staticFile(`audio/sfx/${c.name}.wav`)} volume={c.gain * (hasVoice ? 0.6 : 0.85)} />
          </Sequence>
        ) : null,
      )}
    </>
  );
};

export const FilmComposition: React.FC<{ film: Film; captions?: boolean }> = ({ film, captions: showCaptions = true }) => {
  const { scenes } = place(film);
  return (
    <AbsoluteFill style={{ background: C.black }}>
      {scenes.map((p) => (
        <Sequence key={p.scene.id} from={p.start} durationInFrames={p.frames} name={p.scene.id}>
          <Shell p={p} inKind={p.index > 0 ? film.scenes[p.index - 1].transition?.kind : undefined}>
            <SceneView scene={p.scene} />
          </Shell>
        </Sequence>
      ))}
      {showCaptions && <Captions items={captions(film)} />}
      <Soundtrack film={film} />
    </AbsoluteFill>
  );
};

/** For the studio: a fade-free view of one scene, to tune it. */
export const SceneOnly: React.FC<{ film: Film; id: string }> = ({ film, id }) => {
  const s = film.scenes.find((x) => x.id === id);
  const frame = useCurrentFrame();
  return s ? <SceneView scene={s} /> : <AbsoluteFill style={{ color: "white" }}>{interpolate(frame, [0, 1], [0, 1])}</AbsoluteFill>;
};
