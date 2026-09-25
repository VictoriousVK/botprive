"use client";

import { ArrowRight, CircleCheck, FlaskConical, Radar, ShieldCheck } from "lucide-react";
import Link from "next/link";
import { RobotGrid } from "@/components/products";
import { Notice, Reveal, SectionHead } from "@/components/ui";

const STEPS = [
  { icon: FlaskConical, title: "Backtest et simulation", text: "Chaque robot tourne d'abord sur l'historique puis en simulation, avec les mêmes règles de risque qu'en réel." },
  { icon: Radar, title: "Compte papier puis démo", text: "Prix réels de MT5, ordres simulés, puis compte démo chez votre courtier, pendant plusieurs semaines." },
  { icon: ShieldCheck, title: "Réel, sous trois verrous", text: "Autorisation serveur, phrase de confirmation, mot de passe et 2FA : rien ne part en réel par accident." },
];

export function RobotsView() {
  return (
    <div className="container-x py-14">
      <SectionHead eyebrow="Robots MT5" title={<>Des robots issus de <span className="text-gradient">nos propres EA</span>.</>}>
        Les stratégies ICT de Victor Faye et Khalifa Diop, réécrites pour la plateforme : mêmes fenêtres horaires, mêmes setups (Silver Bullet, Macro Breaker),
        même gestion du trade, contrôlées par un moteur de risque commun.
      </SectionHead>
      <div className="mt-10">
        <RobotGrid />
      </div>
      <Notice kind="warn" className="mt-8">
        Les robots sont en <strong>bêta</strong>. Leur historique vérifié est en cours de constitution sur comptes démo suivis ; aucun résultat n&apos;est publié
        avant d&apos;avoir été mesuré. Le trading comporte un risque de perte en capital.
      </Notice>
      <section className="mt-20">
        <SectionHead eyebrow="Mise en service" title="Du backtest au compte réel, sans raccourci." />
        <div className="mt-10 grid gap-4 md:grid-cols-3">
          {STEPS.map((s, i) => (
            <Reveal key={s.title} delay={i * 0.08}>
              <div className="card h-full p-6">
                <div className="flex items-center gap-3">
                  <span className="num text-sm text-faint">0{i + 1}</span>
                  <s.icon className="size-5 text-brand-300" />
                </div>
                <h3 className="mt-4 font-semibold">{s.title}</h3>
                <p className="mt-2 text-sm leading-relaxed text-muted">{s.text}</p>
              </div>
            </Reveal>
          ))}
        </div>
      </section>
      <section className="mt-20 grid items-center gap-8 lg:grid-cols-2">
        <div>
          <SectionHead eyebrow="Licence" title="Inclus dans les offres Pro et Elite." />
          <ul className="mt-6 grid gap-3 text-sm">
            {["Pro : une licence au choix (ICT Pro v6.20 ou ICT v6)", "Elite : tous les robots, et le prochain en accès anticipé", "Mises à jour des robots incluses pendant l'abonnement"].map((t) => (
              <li key={t} className="flex gap-2.5"><CircleCheck className="mt-0.5 size-4 shrink-0 text-up-400" /> {t}</li>
            ))}
          </ul>
        </div>
        <div className="flex flex-col gap-3 sm:flex-row lg:justify-end">
          <Link href="/tarifs/" className="btn btn-primary">Voir les offres <ArrowRight className="size-4" /></Link>
          <a href="/console" className="btn btn-ghost">Console de trading</a>
        </div>
      </section>
    </div>
  );
}
