"use client";

import { ArrowRight, BookOpenCheck, ChevronDown, Clapperboard, FileClock, FingerprintPattern, KeyRound, ListChecks, Lock, MonitorSmartphone, CirclePlay, ScrollText, ShieldCheck } from "lucide-react";
import Link from "next/link";
import { useState } from "react";
import { VFMark, Initials } from "@/components/brand";
import { CopySteps, RiskControls } from "@/components/copy";
import { Hero } from "@/components/hero";
import { Pricing, RobotGrid, SoonBadge } from "@/components/products";
import { Reveal, SectionHead } from "@/components/ui";
import { useSession } from "@/lib/session";

export default function Home() {
  return (
    <>
      <Hero />
      <Facts />
      <section id="robots" className="container-x scroll-mt-24 py-20">
        <SectionHead eyebrow="Robots MT5" title={<>Nos EA, portés sur une plateforme <span className="text-gradient">sous contrôle</span>.</>}>
          Les deux robots ICT de la phase bêta reprennent la logique de nos Expert Advisors MQL5. Un robot plus performant est en développement : il ne rejoindra le
          catalogue qu&apos;après plusieurs mois sur compte démo suivi.
        </SectionHead>
        <div className="mt-10">
          <RobotGrid />
        </div>
      </section>
      <CopySection />
      <AcademySection />
      <SecuritySection />
      <section id="offres" className="container-x scroll-mt-24 py-20">
        <SectionHead center eyebrow="Offres" title="Un accès complet, payé avec Wave.">
          Commencez gratuitement. Passez à l&apos;offre supérieure quand vous êtes prêt, pour un mois, trois mois ou un an.
        </SectionHead>
        <div className="mt-10">
          <Pricing />
        </div>
      </section>
      <Founders />
      <Faq />
      <FinalCta />
    </>
  );
}

function Facts() {
  const facts = [
    ["2", "robots ICT", "ICT Pro v6.20 et ICT v6, issus de nos EA MQL5"],
    ["3", "modes", "simulation, papier, compte MT5"],
    ["3", "verrous", "avant tout ordre sur un compte réel"],
    ["Wave", "en FCFA", "paiement mobile, sans carte bancaire"],
  ];
  return (
    <section className="border-y border-white/5 bg-ink-900/50">
      <div className="container-x grid grid-cols-2 gap-px md:grid-cols-4">
        {facts.map(([big, unit, text], i) => (
          <Reveal key={text} delay={i * 0.06} className="px-2 py-7 sm:px-5">
            <div className="flex items-baseline gap-2">
              <span className="num text-3xl font-semibold text-white">{big}</span>
              <span className="text-sm font-semibold text-brand-300">{unit}</span>
            </div>
            <p className="mt-1 text-sm text-muted">{text}</p>
          </Reveal>
        ))}
      </div>
    </section>
  );
}

function CopySection() {
  const [v, setV] = useState({ allocation: 2000, multiplier: 1, max_drawdown_pct: 20 });
  return (
    <section id="copytrading" className="relative scroll-mt-24 overflow-hidden py-20">
      <div className="absolute inset-x-0 top-0 -z-10 h-full bg-gradient-to-b from-brand-500/[0.06] to-transparent" aria-hidden />
      <div className="container-x grid items-center gap-12 lg:grid-cols-2">
        <div>
          <SectionHead eyebrow="Copytrading moderne" title={<>Copiez une stratégie, <span className="text-gradient">à vos conditions</span>.</>}>
            Vous choisissez la stratégie, le capital, la taille des positions et la perte à partir de laquelle tout s&apos;arrête. Chaque chiffre affiché vient
            du journal de la plateforme.
          </SectionHead>
          <div className="mt-8">
            <CopySteps />
          </div>
          <div className="mt-8 flex flex-wrap items-center gap-3">
            <Link href="/copytrading/" className="btn btn-primary">
              Essayer en démo <ArrowRight className="size-4" />
            </Link>
            <span className="chip chip-gold">
              <Lock className="size-3" /> Copie sur compte réel : après validation juridique
            </span>
          </div>
        </div>
        <Reveal>
          <div className="card p-6 shadow-[var(--shadow-glow)] sm:p-8">
            <div className="flex items-center justify-between">
              <p className="eyebrow">Vos réglages</p>
              <span className="chip">Simulateur</span>
            </div>
            <div className="mt-6">
              <RiskControls value={v} onChange={setV} />
            </div>
            <p className="mt-5 text-xs leading-relaxed text-faint">
              Ce simulateur traduit vos réglages en montants. Il n&apos;affiche aucun rendement : le résultat d&apos;une copie dépend du marché et de la stratégie
              suivie.
            </p>
          </div>
        </Reveal>
      </div>
    </section>
  );
}

function AcademySection() {
  const { site } = useSession();
  const planned = site?.academy.planned ?? [];
  const features = [
    { icon: Clapperboard, text: "Vidéos longues découpées en parties, jusqu'à 40 minutes et plus" },
    { icon: ListChecks, text: "Chapitres cliquables pour retrouver un passage précis" },
    { icon: CirclePlay, text: "Reprise automatique là où vous vous êtes arrêté" },
    { icon: MonitorSmartphone, text: "Lecture fluide sur téléphone, adaptée à votre connexion" },
  ];
  return (
    <section id="academie" className="container-x scroll-mt-24 py-20">
      <div className="grid gap-12 lg:grid-cols-[1fr_1.1fr]">
        <div>
          <SectionHead eyebrow="Académie" title={<>Apprendre la méthode, <span className="text-gradient">partie par partie</span>.</>}>
            Les cours vidéo de Khalifa Diop et Victor Faye arrivent au fil des tournages. Créez votre compte pour être prévenu de chaque nouvelle partie.
          </SectionHead>
          <ul className="mt-8 grid gap-3">
            {features.map((f) => (
              <li key={f.text} className="flex items-center gap-3 text-sm text-fg/90">
                <f.icon className="size-5 shrink-0 text-brand-300" /> {f.text}
              </li>
            ))}
          </ul>
          <Link href="/academie/" className="btn btn-ghost mt-8">
            Voir l&apos;académie <ArrowRight className="size-4" />
          </Link>
        </div>
        <div className="grid content-center gap-4">
          {planned.map((p, i) => (
            <Reveal key={p.slug} delay={i * 0.08}>
              <Link href={`/academie/cours/?c=${p.slug}`} className="card card-hover flex items-center gap-5 p-5">
                <span className="num grid size-14 shrink-0 place-items-center rounded-2xl border border-white/10 bg-gradient-to-br from-brand-500/20 to-up-500/10 text-lg font-semibold text-brand-300">
                  0{i + 1}
                </span>
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <h3 className="font-semibold">{p.title}</h3>
                    <SoonBadge />
                  </div>
                  <p className="mt-1 text-sm text-muted">{p.subtitle}</p>
                </div>
                <BookOpenCheck className="hidden size-5 shrink-0 text-faint sm:block" />
              </Link>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}

function SecuritySection() {
  const items = [
    { icon: KeyRound, title: "Trois verrous avant le réel", text: "Autorisation serveur, phrase de confirmation et mot de passe (plus 2FA) : aucun robot n'envoie d'ordre réel par accident." },
    { icon: FingerprintPattern, title: "Double authentification", text: "Codes à usage unique compatibles Google Authenticator, Aegis ou 1Password." },
    { icon: ShieldCheck, title: "Vos autres EA intacts", text: "La plateforme ne touche qu'à ses propres positions (numéro magique 770077)." },
    { icon: FileClock, title: "Journal infalsifiable", text: "Chaque décision, ordre et action d'un opérateur est enregistré et chaîné." },
    { icon: Lock, title: "Arrêt d'urgence", text: "Perte maximale, perte du jour, exposition : les limites de risque s'appliquent à tous les robots." },
    { icon: ScrollText, title: "Chiffres vérifiables", text: "Aucune performance saisie à la main : tout vient du journal, avec sa source (simulation, papier ou MT5)." },
  ];
  return (
    <section className="border-y border-white/5 bg-ink-900/40 py-20">
      <div className="container-x">
        <SectionHead center eyebrow="Sécurité" title="Conçu pour protéger votre capital d'abord.">
          Le risque n&apos;est jamais une option que l&apos;on peut désactiver.
        </SectionHead>
        <div className="mt-12 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {items.map((it, i) => (
            <Reveal key={it.title} delay={(i % 3) * 0.06}>
              <div className="card h-full p-6">
                <it.icon className="size-6 text-brand-300" />
                <h3 className="mt-4 font-semibold">{it.title}</h3>
                <p className="mt-2 text-sm leading-relaxed text-muted">{it.text}</p>
              </div>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}

function Founders() {
  const { site } = useSession();
  const founders = site?.founders ?? [];
  return (
    <section className="container-x py-20">
      <SectionHead center eyebrow="Fondateurs" title="Deux traders derrière chaque ligne de code.">
        Liberté Financière est née de la rencontre entre l&apos;expérience du marché et la rigueur des données.
      </SectionHead>
      <div className="mx-auto mt-12 grid max-w-4xl gap-5 md:grid-cols-2">
        {founders.map((f, i) => (
          <Reveal key={f.name} delay={i * 0.1}>
            <div className="card h-full p-7">
              <div className="flex items-center gap-4">
                {f.mark === "vf" ? (
                  <span className="grid size-16 place-items-center rounded-2xl border border-gold-500/40 bg-gradient-to-br from-ink-700 to-ink-900">
                    <VFMark size={40} />
                  </span>
                ) : (
                  <Initials text={f.initials} className="size-16 text-lg" />
                )}
                <div>
                  <h3 className="font-[family-name:var(--font-display)] text-xl font-bold">{f.name}</h3>
                  <p className="text-sm text-gold-300">{f.role}</p>
                </div>
              </div>
              <p className="mt-5 text-sm leading-relaxed text-muted">{f.bio}</p>
            </div>
          </Reveal>
        ))}
      </div>
    </section>
  );
}

const FAQ: [string, string][] = [
  ["Les robots garantissent-ils des gains ?", "Non. Aucun robot ni aucune méthode ne garantit de gains, et le trading peut faire perdre tout le capital engagé. Nous publions uniquement des résultats issus du journal de la plateforme, avec leur source (simulation, papier ou compte MT5)."],
  ["Comment payer avec Wave ?", "Choisissez une offre et une durée, puis payez dans l'application Wave. Votre accès est activé dès que le paiement est confirmé par Wave (ou vérifié par l'équipe pour un transfert). Il n'y a pas de prélèvement automatique."],
  ["Le copytrading est-il ouvert ?", "La copie est ouverte en démonstration : vous suivez une stratégie avec vos réglages et voyez le résultat, sans ordre réel. La copie sur votre propre compte MT5 ouvrira après validation par un avocat du cadre réglementaire (AMF-UMOA)."],
  ["Mes fonds sont-ils chez Liberté Financière ?", "Non. Votre capital reste sur votre compte chez votre courtier. La plateforme n'encaisse que l'abonnement."],
  ["Quand les cours seront-ils disponibles ?", "Les parcours sont en tournage. Ils seront publiés partie par partie ; créez un compte gratuit pour être prévenu."],
];

function Faq() {
  return (
    <section className="container-x py-20">
      <SectionHead center eyebrow="Questions fréquentes" title="Ce que vous devez savoir." />
      <div className="mx-auto mt-10 grid max-w-3xl gap-3">
        {FAQ.map(([q, a]) => (
          <details key={q} className="card group p-5 open:border-brand-400/30">
            <summary className="flex cursor-pointer list-none items-center justify-between gap-4 font-semibold">
              {q}
              <ChevronDown className="size-5 shrink-0 text-faint transition-transform group-open:rotate-180" />
            </summary>
            <p className="mt-3 text-sm leading-relaxed text-muted">{a}</p>
          </details>
        ))}
      </div>
    </section>
  );
}

function FinalCta() {
  return (
    <section className="container-x">
      <Reveal>
        <div className="relative overflow-hidden rounded-3xl border border-brand-400/25 bg-gradient-to-br from-brand-600/30 via-ink-800 to-ink-900 px-6 py-14 text-center sm:px-12">
          <div className="grid-bg absolute inset-0 -z-0 opacity-60" aria-hidden />
          <div className="relative">
            <h2 className="h-section mx-auto max-w-2xl">Votre liberté financière se construit avec méthode.</h2>
            <p className="mx-auto mt-4 max-w-xl text-muted">Compte gratuit, sans carte bancaire. Commencez par la démo, passez au réel quand vous êtes prêt.</p>
            <div className="mt-8 flex flex-col justify-center gap-3 sm:flex-row">
              <Link href="/compte/?vue=inscription" className="btn btn-primary">
                Créer mon compte <ArrowRight className="size-4" />
              </Link>
              <Link href="/tarifs/" className="btn btn-ghost">Voir les offres</Link>
            </div>
          </div>
        </div>
      </Reveal>
    </section>
  );
}
