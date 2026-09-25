"use client";

import { CircleCheck, MessageCircle, QrCode, Smartphone, Timer } from "lucide-react";
import { PaymentMethods, Pricing, WhatsAppButton } from "@/components/products";
import { Reveal, SectionHead } from "@/components/ui";
import { useSession } from "@/lib/session";

export function TarifsView() {
  const { site } = useSession();
  const steps = [
    { icon: CircleCheck, title: "Choisissez", text: "Un abonnement (1, 3 ou 12 mois), une formation (paiement unique, accès à vie) ou le groupe Elite." },
    { icon: Smartphone, title: "Payez avec Wave", text: site?.wave === "api" ? "Vous êtes redirigé vers Wave pour valider le paiement dans l'application." : `Envoyez le montant au ${site?.contact.whatsapp_display || "numéro Wave indiqué"}, puis saisissez l'ID de la transaction.` },
    { icon: Timer, title: "Accès activé", text: site?.wave === "api" ? "Dès la confirmation de Wave, sans action de votre part." : "Dès que l'équipe a vérifié la transaction, en général dans la journée." },
  ];
  return (
    <div className="container-x py-14">
      <SectionHead center eyebrow="Offres" title={<>Abonnements, formations, <span className="text-gradient">mentorat</span>.</>}>
        Prix en dollars, payés en FCFA avec Wave. Pas de prélèvement automatique : vous payez une durée, vous la prolongez quand vous voulez.
      </SectionHead>
      <div className="mt-8">
        <PaymentMethods />
      </div>
      <div className="mt-12">
        <Pricing />
      </div>
      <section className="mt-20">
        <div className="card overflow-hidden">
          <div className="grid lg:grid-cols-[0.9fr_1.1fr]">
            <div className="relative bg-gradient-to-br from-[#1dc8ff]/15 to-transparent p-8">
              <span className="grid size-12 place-items-center rounded-2xl bg-[#1dc8ff] text-[#06243a]"><QrCode className="size-6" /></span>
              <h2 className="mt-5 font-[family-name:var(--font-display)] text-2xl font-bold">Paiement mobile Wave</h2>
              <p className="mt-3 text-sm leading-relaxed text-muted">
                Payez depuis votre téléphone, en FCFA, sans carte bancaire. Orange Money, la carte bancaire (Stripe) et PayPal arriveront ensuite.
              </p>
              <div className="mt-6">
                <WhatsAppButton text="Bonjour, j'ai une question sur les offres Liberté Financière." label="Une question ? WhatsApp" />
              </div>
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
      <p className="mt-10 flex items-center justify-center gap-2 text-center text-xs text-faint">
        <MessageCircle className="size-3.5" /> Mentorat individuel sur candidature : écrivez-nous sur WhatsApp.
      </p>
    </div>
  );
}
