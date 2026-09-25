"use client";

import { CircleCheck, QrCode, Smartphone, Timer } from "lucide-react";
import { Pricing } from "@/components/products";
import { Reveal, SectionHead } from "@/components/ui";
import { useSession } from "@/lib/session";

export function TarifsView() {
  const { site } = useSession();
  const steps = [
    { icon: CircleCheck, title: "Choisissez", text: "Une offre et une durée : 1 mois, 3 mois ou 1 an (deux mois offerts)." },
    { icon: Smartphone, title: "Payez avec Wave", text: site?.wave === "api" ? "Vous êtes redirigé vers Wave pour valider le paiement dans l'application." : "Envoyez le montant au compte Wave indiqué, puis saisissez l'ID de la transaction." },
    { icon: Timer, title: "Accès activé", text: site?.wave === "api" ? "Dès la confirmation de Wave, sans action de votre part." : "Dès que l'équipe a vérifié la transaction, en général dans la journée." },
  ];
  return (
    <div className="container-x py-14">
      <SectionHead center eyebrow="Offres" title={<>Choisissez votre <span className="text-gradient">niveau d&apos;accès</span>.</>}>
        Tous les prix sont en FCFA. Pas d&apos;abonnement caché : vous payez une durée, vous la prolongez quand vous voulez.
      </SectionHead>
      <div className="mt-10">
        <Pricing />
      </div>
      <section className="mt-20">
        <div className="card overflow-hidden">
          <div className="grid lg:grid-cols-[0.9fr_1.1fr]">
            <div className="relative bg-gradient-to-br from-[#1dc8ff]/15 to-transparent p-8">
              <span className="grid size-12 place-items-center rounded-2xl bg-[#1dc8ff] text-[#06243a]"><QrCode className="size-6" /></span>
              <h2 className="mt-5 font-[family-name:var(--font-display)] text-2xl font-bold">Paiement mobile Wave</h2>
              <p className="mt-3 text-sm leading-relaxed text-muted">
                Payez depuis votre téléphone, en FCFA, sans carte bancaire. Les autres moyens (Orange Money, carte) arriveront avec l&apos;agrégateur de paiement.
              </p>
            </div>
            <ol className="grid gap-0 divide-y divide-white/5">
              {steps.map((s, i) => (
                <Reveal key={s.title} delay={i * 0.06}>
                  <li className="flex gap-4 p-6">
                    <span className="grid size-10 shrink-0 place-items-center rounded-xl border border-white/10 text-brand-300"><s.icon className="size-5" /></span>
                    <div>
                      <div className="font-semibold"><span className="num mr-2 text-faint">0{i + 1}</span>{s.title}</div>
                      <p className="mt-1 text-sm text-muted">{s.text}</p>
                    </div>
                  </li>
                </Reveal>
              ))}
            </ol>
          </div>
        </div>
      </section>
    </div>
  );
}
