"use client";

import { ArrowLeft, CircleCheck, Clock, Lock, Play } from "lucide-react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useEffect, useMemo, useRef, useState } from "react";
import { Waitlist } from "@/components/products";
import { Notice, Spinner } from "@/components/ui";
import { api, clock, duration, type Course, type Part } from "@/lib/api";
import { useApi, useSession } from "@/lib/session";

function withStart(src: string, t: number) {
  if (!t) return src;
  if (src.includes("youtube-nocookie.com")) return `${src}&start=${Math.floor(t)}&autoplay=1`;
  if (src.includes("player.vimeo.com")) return `${src}#t=${Math.floor(t)}s`;
  return src;
}

export function CourseView() {
  const slug = useSearchParams().get("c") ?? "";
  const { me } = useSession();
  const { data: course, loading, error, reload } = useApi<Course>(slug ? `/api/site/courses/${encodeURIComponent(slug)}` : null, [me?.id]);
  const [current, setCurrent] = useState<string | null>(null);
  const [start, setStart] = useState(0);
  const part = useMemo(() => course?.parts.find((p) => p.id === current) ?? course?.parts.find((p) => !p.locked) ?? null, [course, current]);

  if (!slug) return <div className="container-x py-14"><Notice kind="error">Cours introuvable.</Notice></div>;
  if (loading && !course) return <div className="container-x py-14"><Spinner /></div>;
  if (error || !course) return <div className="container-x py-14"><Notice kind="error">{error ?? "Cours introuvable."}</Notice></div>;

  const total = course.parts.reduce((s, p) => s + p.duration_s, 0);
  const done = course.parts.filter((p) => p.progress?.completed).length;

  return (
    <div className="container-x py-10">
      <Link href="/academie/" className="inline-flex items-center gap-2 text-sm text-muted hover:text-white"><ArrowLeft className="size-4" /> Académie</Link>
      <div className="mt-4 flex flex-wrap items-center gap-3">
        <h1 className="h-section">{course.title}</h1>
        <span className={`chip ${course.status === "soon" ? "chip-gold" : "chip-green"}`}>{course.status === "soon" ? "En préparation" : course.access_label}</span>
      </div>
      {course.subtitle && <p className="mt-2 max-w-3xl text-muted">{course.subtitle}</p>}

      {course.status === "soon" || course.parts.length === 0 ? (
        <div className="card mt-8 grid gap-4 p-8 text-center">
          <p className="font-semibold">Ce cours est en cours de tournage.</p>
          <p className="mx-auto max-w-lg text-sm text-muted">Les vidéos seront publiées partie par partie. Laissez votre e-mail pour recevoir la première dès sa sortie.</p>
          <div className="mx-auto w-full max-w-md"><Waitlist interest="academie" cta="Me prévenir" /></div>
        </div>
      ) : (
        <div className="mt-8 grid gap-6 lg:grid-cols-[1fr_22rem]">
          <div className="min-w-0">
            {part ? (
              <PartPlayer key={`${part.id}-${start}`} part={part} start={start || part.progress?.position_s || 0} signedIn={!!me} onSaved={reload} />
            ) : (
              <LockedPanel signedIn={!!me} />
            )}
            {part && (
              <div className="mt-5">
                <h2 className="text-lg font-semibold">
                  <span className="num mr-2 text-faint">Partie {part.position}</span>
                  {part.title}
                </h2>
                {part.summary && <p className="mt-2 whitespace-pre-line text-sm leading-relaxed text-muted">{part.summary}</p>}
                {part.chapters.length > 0 && (
                  <div className="mt-5">
                    <h3 className="text-xs font-semibold uppercase tracking-wider text-faint">Chapitres</h3>
                    <ul className="mt-2 grid gap-1 sm:grid-cols-2">
                      {part.chapters.map((c) => (
                        <li key={c.t}>
                          <button className="flex w-full items-center gap-3 rounded-lg px-2 py-1.5 text-left text-sm hover:bg-white/5" onClick={() => setStart(c.t || 0.001)}>
                            <span className="num w-14 shrink-0 text-brand-300">{clock(c.t)}</span>
                            <span className="truncate">{c.title}</span>
                          </button>
                        </li>
                      ))}
                    </ul>
                  </div>
                )}
              </div>
            )}
            {course.description && <p className="mt-8 whitespace-pre-line text-sm leading-relaxed text-muted">{course.description}</p>}
          </div>
          <aside className="card h-fit p-4 lg:sticky lg:top-24">
            <div className="flex items-center justify-between px-2 pb-3 text-xs text-faint">
              <span>{course.parts.length} parties · <span className="num">{duration(total)}</span></span>
              {me && <span>{done}/{course.parts.length} vues</span>}
            </div>
            <ol className="grid gap-1">
              {course.parts.map((p) => (
                <li key={p.id}>
                  <button
                    onClick={() => { if (!p.locked) { setCurrent(p.id); setStart(0); } }}
                    disabled={p.locked}
                    className={`flex w-full items-center gap-3 rounded-xl px-3 py-3 text-left text-sm transition-colors ${part?.id === p.id ? "bg-brand-500/15 ring-1 ring-brand-400/30" : "hover:bg-white/5"} ${p.locked ? "cursor-not-allowed opacity-60" : ""}`}
                  >
                    <span className="grid size-8 shrink-0 place-items-center rounded-lg border border-white/10">
                      {p.locked ? <Lock className="size-3.5" /> : p.progress?.completed ? <CircleCheck className="size-4 text-up-400" /> : <Play className="size-3.5 text-brand-300" />}
                    </span>
                    <span className="min-w-0 flex-1">
                      <span className="block truncate font-medium">{p.position}. {p.title}</span>
                      <span className="num flex items-center gap-2 text-xs text-faint">
                        <Clock className="size-3" /> {duration(p.duration_s)} {p.free_preview && <span className="text-up-300">· gratuite</span>}
                      </span>
                    </span>
                  </button>
                </li>
              ))}
            </ol>
            {!course.unlocked && <div className="mt-3 border-t border-white/5 p-2 pt-4"><LockedPanel signedIn={!!me} compact /></div>}
          </aside>
        </div>
      )}
    </div>
  );
}

function LockedPanel({ signedIn, compact = false }: { signedIn: boolean; compact?: boolean }) {
  return (
    <div className={compact ? "grid gap-2 text-sm" : "card grid aspect-video place-items-center p-6 text-center"}>
      <div className="grid gap-3">
        {!compact && <Lock className="mx-auto size-8 text-brand-300" />}
        <p className={compact ? "text-muted" : "font-semibold"}>La suite de ce cours est réservée aux membres qui y ont accès.</p>
        <Link href={signedIn ? "/tarifs/" : "/compte/?vue=inscription"} className="btn btn-primary btn-sm mx-auto">
          {signedIn ? "Voir les offres" : "Créer un compte gratuit"}
        </Link>
      </div>
    </div>
  );
}

function PartPlayer({ part, start, signedIn, onSaved }: { part: Part; start: number; signedIn: boolean; onSaved: () => void }) {
  const video = useRef<HTMLVideoElement>(null);
  const last = useRef(0);
  const [saved, setSaved] = useState(!!part.progress?.completed);

  const save = async (position: number, completed = false) => {
    if (!signedIn) return;
    try {
      await api("/api/m/progress", { method: "POST", body: { part_id: part.id, position_s: Math.floor(position), completed } });
      if (completed) {
        setSaved(true);
        onSaved();
      }
    } catch {
      /* progress is best-effort */
    }
  };

  useEffect(() => {
    const v = video.current;
    if (v && start) v.currentTime = start;
  }, [start]);

  if (!part.player) return null;
  return (
    <div>
      <div className="relative aspect-video overflow-hidden rounded-2xl border border-white/10 bg-black shadow-2xl">
        {part.player.kind === "video" ? (
          <video
            ref={video} src={part.player.src} controls playsInline preload="metadata" className="size-full"
            onTimeUpdate={(e) => {
              const t = e.currentTarget.currentTime;
              if (Math.abs(t - last.current) > 15) {
                last.current = t;
                save(t);
              }
            }}
            onPause={(e) => save(e.currentTarget.currentTime)}
            onEnded={(e) => save(e.currentTarget.duration, true)}
          />
        ) : (
          <iframe
            src={withStart(part.player.src, start)} title={part.title} className="size-full" loading="lazy"
            allow="accelerometer; encrypted-media; fullscreen; picture-in-picture; autoplay" allowFullScreen referrerPolicy="strict-origin-when-cross-origin"
          />
        )}
      </div>
      {signedIn && part.player.kind === "iframe" && (
        <div className="mt-3 flex justify-end">
          <button className="btn btn-ghost btn-sm" onClick={() => save(part.duration_s, true)} disabled={saved}>
            <CircleCheck className="size-4" /> {saved ? "Partie vue" : "Marquer comme vue"}
          </button>
        </div>
      )}
    </div>
  );
}
