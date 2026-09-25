"use client";

import { AnimatePresence, motion } from "framer-motion";
import { Scale, Users, X } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { CopySteps, FollowCard, FollowForm, LeaderCard } from "@/components/copy";
import { Waitlist } from "@/components/products";
import { Empty, Notice, SectionHead, Spinner } from "@/components/ui";
import { api, type Follow, type Leader } from "@/lib/api";
import { useApi, useSession } from "@/lib/session";

export function CopyView() {
  const { me } = useSession();
  const { data, loading, error } = useApi<{ mode: string; leaders: Leader[] }>("/api/site/leaders");
  const [picked, setPicked] = useState<Leader | null>(null);
  const [mine, setMine] = useState<Follow[] | null>(null);

  const loadMine = useCallback(() => {
    if (me) api<Follow[]>("/api/m/copy").then(setMine).catch(() => setMine([]));
  }, [me]);
  useEffect(loadMine, [loadMine]);

  const stop = async (f: Follow) => {
    await api(`/api/m/copy/${f.id}/stop`, { method: "POST" });
    loadMine();
  };

  return (
    <div className="container-x py-14">
      <div className="grid gap-10 lg:grid-cols-[1.1fr_0.9fr]">
        <SectionHead eyebrow="Copytrading" title={<>Suivez une stratégie, <span className="text-gradient">gardez vos règles</span>.</>}>
          Choisissez une stratégie publiée par l&apos;équipe, réglez votre capital, votre multiplicateur et votre perte maximale, et suivez le résultat en temps
          réel. La copie s&apos;arrête seule si votre seuil de perte est atteint.
        </SectionHead>
        <div className="card p-6">
          <CopySteps />
        </div>
      </div>

      <Notice kind="warn" className="mt-10">
        <strong>Démo uniquement pour l&apos;instant.</strong> La copie d&apos;ordres sur votre propre compte MT5 est une activité réglementée (gestion pour compte de
        tiers, conseil en investissement) ; elle ouvrira après validation par un avocat du cadre applicable (AMF-UMOA et pays concernés).
      </Notice>

      {me && mine && mine.length > 0 && (
        <section className="mt-14">
          <h2 className="font-[family-name:var(--font-display)] text-xl font-bold">Mes copies</h2>
          <div className="mt-5 grid gap-4 lg:grid-cols-2">
            {mine.map((f) => (
              <FollowCard key={f.id} f={f} onStop={stop} />
            ))}
          </div>
        </section>
      )}

      <section className="mt-14">
        <h2 className="font-[family-name:var(--font-display)] text-xl font-bold">Stratégies disponibles</h2>
        <div className="mt-5">
          {loading ? (
            <Spinner />
          ) : error ? (
            <Notice kind="error">{error}</Notice>
          ) : data?.mode === "off" ? (
            <Empty icon={<Scale className="size-7" />} title="Le copytrading n'est pas encore ouvert">Laissez votre e-mail pour être prévenu.</Empty>
          ) : data && data.leaders.length > 0 ? (
            <div className="grid gap-5 md:grid-cols-2 xl:grid-cols-3">
              {data.leaders.map((l) => (
                <LeaderCard key={l.id} l={l} onFollow={setPicked} />
              ))}
            </div>
          ) : (
            <Empty icon={<Users className="size-7" />} title="Les premières stratégies arrivent">
              Elles seront publiées dès qu&apos;elles auront un historique mesuré par la plateforme. Laissez votre e-mail pour être prévenu.
            </Empty>
          )}
        </div>
        <div className="mx-auto mt-8 max-w-md">
          <Waitlist interest="copytrading" cta="Prévenez-moi de l'ouverture" />
        </div>
      </section>

      <AnimatePresence>
        {picked && (
          <motion.div className="fixed inset-0 z-[60] grid place-items-end bg-black/60 backdrop-blur-sm sm:place-items-center" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} onClick={() => setPicked(null)}>
            <motion.div
              role="dialog" aria-modal="true" aria-label={`Copier ${picked.name}`}
              className="card relative max-h-[92vh] w-full overflow-y-auto rounded-b-none p-6 sm:max-w-lg sm:rounded-b-[var(--radius-card)] sm:p-8"
              initial={{ y: 40, opacity: 0 }} animate={{ y: 0, opacity: 1 }} exit={{ y: 40, opacity: 0 }} transition={{ type: "spring", stiffness: 320, damping: 32 }}
              onClick={(e) => e.stopPropagation()}
            >
              <button className="absolute right-4 top-4 rounded-lg p-1 text-muted hover:text-white" onClick={() => setPicked(null)} aria-label="Fermer"><X className="size-5" /></button>
              <FollowForm leader={picked} onCancel={() => setPicked(null)} onDone={() => { setPicked(null); loadMine(); }} />
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
