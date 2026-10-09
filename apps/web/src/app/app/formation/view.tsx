"use client";

import { CirclePlay, GraduationCap, Lock, MonitorPlay } from "lucide-react";
import Link from "next/link";
import { AppShell } from "@/components/app-shell";
import { useLoad } from "@/components/app-ui";
import { Empty, Notice, Spinner } from "@/components/ui";
import { when } from "@/lib/app";

type MyCourse = {
  slug: string; title: string; subtitle: string; level: string; status: "published" | "soon"; access: string; access_label: string; unlocked: boolean;
  parts: number; open_parts: number; completed: number; duration_s: number; next: { id: string; title: string; position: number } | null; last_seen: number | null;
};

const hm = (s: number) => (s >= 3600 ? `${Math.floor(s / 3600)} h ${String(Math.round((s % 3600) / 60)).padStart(2, "0")}` : `${Math.max(1, Math.round(s / 60))} min`);
const UNLOCK_PAGE: Record<string, string> = { formation_ict: "/formation-ict/" };

export function FormationView() {
  return (
    <AppShell title="Formation" subtitle="Vos cours vidéo, là où vous en êtes, et le Mentor pour les questions">
      <Courses />
    </AppShell>
  );
}

function Courses() {
  const { data, error } = useLoad<MyCourse[]>("/api/m/courses");
  if (error) return <Notice kind="error">{error}</Notice>;
  if (!data) return <Spinner />;
  if (!data.length) return <Empty icon={<MonitorPlay className="size-7" />} title="Aucun cours publié pour l'instant">Les vidéos de la formation apparaîtront ici dès leur mise en ligne.</Empty>;
  const current = data.find((c) => c.unlocked && c.completed > 0 && c.next);
  return (
    <div className="grid gap-5">
      {current && current.next && (
        <Link href={`/academie/cours/?c=${current.slug}&p=${current.next.id}`} className="card card-hover flex flex-wrap items-center gap-4 p-5">
          <CirclePlay className="size-9 shrink-0 text-brand-300" aria-hidden />
          <div className="min-w-0 flex-1">
            <div className="text-xs font-semibold uppercase tracking-wider text-faint">Reprendre</div>
            <div className="truncate font-semibold">{current.title} · Partie {current.next.position} : {current.next.title}</div>
          </div>
          <span className="btn btn-primary btn-sm">Continuer</span>
        </Link>
      )}
      <div className="grid gap-5 md:grid-cols-2 xl:grid-cols-3">
        {data.map((c) => <CourseCard key={c.slug} c={c} />)}
      </div>
      <p className="flex items-center gap-2 text-sm text-muted">
        <GraduationCap className="size-4 text-brand-300" aria-hidden /> Une question sur un cours ? <Link href="/app/mentor/" className="text-brand-300 hover:underline">Demandez au Mentor</Link> : il répond à partir des cours auxquels vous avez accès, avec la référence.
      </p>
    </div>
  );
}

function CourseCard({ c }: { c: MyCourse }) {
  const pct = c.open_parts ? Math.round((c.completed / c.open_parts) * 100) : 0;
  const href = c.next ? `/academie/cours/?c=${c.slug}&p=${c.next.id}` : `/academie/cours/?c=${c.slug}`;
  return (
    <div className="card flex flex-col p-5">
      <div className="flex flex-wrap items-center gap-2">
        {c.status === "soon" ? <span className="chip chip-gold">En préparation</span> : c.unlocked ? <span className="chip chip-green">Inclus</span> : <span className="chip"><Lock className="size-3" aria-hidden /> {c.access_label}</span>}
        {c.level && <span className="chip">{c.level}</span>}
      </div>
      <h2 className="mt-3 font-semibold">{c.title}</h2>
      {c.subtitle && <p className="mt-1 line-clamp-2 text-sm text-muted">{c.subtitle}</p>}
      {c.status === "published" && (
        <div className="mt-4">
          <div className="flex justify-between text-xs text-muted">
            <span>{c.parts} partie{c.parts > 1 ? "s" : ""} · {hm(c.duration_s)}</span>
            {c.open_parts > 0 && <span className="num">{c.completed} / {c.open_parts} vue{c.completed > 1 ? "s" : ""}</span>}
          </div>
          {c.open_parts > 0 && (
            <div className="mt-1.5 h-1.5 overflow-hidden rounded-full bg-white/5" role="progressbar" aria-valuenow={pct} aria-valuemin={0} aria-valuemax={100} aria-label={`Progression : ${pct} %`}>
              <div className="h-full rounded-full bg-brand-400" style={{ width: `${pct}%` }} />
            </div>
          )}
          {c.last_seen && <p className="mt-1.5 text-xs text-faint">Vu le {when(c.last_seen * 1000)}</p>}
        </div>
      )}
      <div className="mt-auto flex flex-wrap gap-2 pt-5">
        {c.status === "soon" ? (
          <Link href={`/academie/cours/?c=${c.slug}`} className="btn btn-ghost btn-sm">Être prévenu</Link>
        ) : c.open_parts > 0 ? (
          <Link href={href} className="btn btn-primary btn-sm">{c.completed === 0 ? (c.unlocked ? "Commencer" : "Voir l'extrait gratuit") : c.next ? "Continuer" : "Revoir"}</Link>
        ) : null}
        {!c.unlocked && c.status === "published" && <Link href={UNLOCK_PAGE[c.access] ?? "/tarifs/"} className="btn btn-ghost btn-sm">Débloquer</Link>}
      </div>
    </div>
  );
}
