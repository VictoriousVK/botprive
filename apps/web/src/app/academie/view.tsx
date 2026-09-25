"use client";

import { Clapperboard, Clock, Layers, Lock, Unlock } from "lucide-react";
import Link from "next/link";
import { Waitlist } from "@/components/products";
import { Notice, Reveal, SectionHead, Spinner } from "@/components/ui";
import { duration, type CourseSummary } from "@/lib/api";
import { useApi, useSession } from "@/lib/session";

export function AcademyView() {
  const { me } = useSession();
  const { data, loading, error } = useApi<CourseSummary[]>("/api/site/courses");
  return (
    <div className="container-x py-14">
      <SectionHead eyebrow="Académie" title={<>Des cours vidéo, <span className="text-gradient">partie par partie</span>.</>}>
        Chaque parcours est découpé en vidéos de plusieurs parties, avec chapitres et reprise automatique. Les premières parties de chaque cours sont
        gratuites ; le reste est inclus dans les offres Trader, Pro et Elite.
      </SectionHead>
      <div className="mt-10">
        {loading ? (
          <Spinner />
        ) : error || !data ? (
          <Notice kind="error">{error ?? "Académie indisponible."}</Notice>
        ) : (
          <div className="grid gap-5 md:grid-cols-2 lg:grid-cols-3">
            {data.map((c, i) => (
              <Reveal key={c.slug} delay={(i % 3) * 0.06} className="h-full">
                <CourseCard c={c} unlocked={!!me?.entitlements.includes(c.access)} />
              </Reveal>
            ))}
          </div>
        )}
      </div>
      <div className="card mt-12 flex flex-col items-start gap-5 p-6 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h2 className="font-semibold">Être prévenu des nouvelles vidéos</h2>
          <p className="mt-1 text-sm text-muted">Un e-mail à chaque nouvelle partie publiée, rien d&apos;autre.</p>
        </div>
        <div className="w-full sm:w-auto"><Waitlist interest="academie" cta="Me prévenir" /></div>
      </div>
    </div>
  );
}

function CourseCard({ c, unlocked }: { c: CourseSummary; unlocked: boolean }) {
  const soon = c.status === "soon";
  return (
    <Link href={`/academie/cours/?c=${c.slug}`} className="card card-hover group flex h-full flex-col overflow-hidden">
      <div className="relative grid aspect-[16/8] place-items-center overflow-hidden border-b border-white/5 bg-gradient-to-br from-brand-600/25 via-ink-800 to-up-500/10">
        <div className="grid-bg absolute inset-0 opacity-70" aria-hidden />
        <Clapperboard className="relative size-10 text-brand-300 transition-transform duration-500 group-hover:scale-110" />
        <span className={`chip absolute left-4 top-4 ${soon ? "chip-gold" : "chip-green"}`}>{soon ? "En préparation" : "Disponible"}</span>
        {c.level && <span className="chip absolute right-4 top-4 bg-ink-950/60">{c.level}</span>}
      </div>
      <div className="flex flex-1 flex-col p-5">
        <h3 className="font-[family-name:var(--font-display)] text-lg font-bold">{c.title}</h3>
        <p className="mt-1 text-sm text-muted">{c.subtitle}</p>
        <div className="mt-auto flex flex-wrap items-center gap-x-4 gap-y-2 pt-5 text-xs text-faint">
          <span className="inline-flex items-center gap-1.5"><Layers className="size-3.5" /> {c.parts ? `${c.parts} partie${c.parts > 1 ? "s" : ""}` : "Parties à venir"}</span>
          {c.duration_s > 0 && <span className="num inline-flex items-center gap-1.5"><Clock className="size-3.5" /> {duration(c.duration_s)}</span>}
          <span className="inline-flex items-center gap-1.5">
            {unlocked || c.access === "academy_free" ? <Unlock className="size-3.5 text-up-400" /> : <Lock className="size-3.5" />} {c.access_label}
            {c.free_parts > 0 && !unlocked ? ` · ${c.free_parts} gratuite${c.free_parts > 1 ? "s" : ""}` : ""}
          </span>
        </div>
      </div>
    </Link>
  );
}
