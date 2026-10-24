import Link from "next/link";
import { CLUB, formatDate, formatXof, getCatalog, getSettings, telegramLinkFor, WEEK_DAYS } from "@vk/core";
import { Candles } from "@/components/Candles";
import { PlanCards } from "@/components/PlanCards";
import { TelegramButton } from "@/components/TelegramButton";
import { listPosters } from "@/lib/posters";
import { getDeps } from "@/lib/server";

export const dynamic = "force-dynamic";

const ADVANTAGES = [
  { title: "Nasdaq en direct", text: "Analyse en temps réel et prises de position live sur NAS100." },
  { title: "Questions en live", text: "Tu demandes, je réponds, pendant que le marché bouge." },
  { title: "1 invité spécial chaque semaine", text: "Un trader invité vient trader et échanger en direct avec le club." },
  { title: "Telegram privé", text: "« ICT V_ICT_orious Trader » : cours, support, replays et débriefing complet des trades après chaque live." },
  { title: "Analyses Gold", text: "Lecture du XAUUSD avec les concepts ICT." },
  { title: "Exclusivité XAUUSD", text: "2 stratégies Gold développées et backtestées, réservées aux membres. Bientôt : signaux swing Gold." },
];

const FAQ = [
  {
    q: "Comment se passe le paiement ?",
    a: "En ligne, en FCFA, par Mobile Money (Wave, Orange Money selon le prestataire actif) ou par carte bancaire, via un prestataire de paiement agréé par la BCEAO. Nous ne voyons jamais tes données de carte.",
  },
  {
    q: "Le renouvellement est-il automatique ?",
    a: "Par carte : oui, uniquement si tu coches la case d'accord ; tu peux l'annuler à tout moment depuis ton espace membre. Par Mobile Money : non, le prélèvement automatique n'existe pas ; tu reçois un rappel à J-3, J-1 et le jour J avec un lien de paiement en 1 clic.",
  },
  {
    q: "Si je renouvelle en avance, je perds des jours ?",
    a: "Non. La nouvelle période commence à la fin de la période en cours. Ton renouvellement est calé sur ta date d'activation : activé le 12, renouvelé le 12.",
  },
  {
    q: "Comment j'accède aux salons privés sur Discord ?",
    a: "Tu te connectes avec ton compte Discord au moment de l'inscription. Dès que le paiement est confirmé par le prestataire, le rôle membre t'est attribué automatiquement (en général en quelques secondes). Si tu n'es pas encore sur le serveur, tu y es ajouté.",
  },
  {
    q: "Et si j'oublie de renouveler ?",
    a: `Tu gardes l'accès pendant un délai de grâce de ${CLUB.graceDays} jours. Ensuite, le rôle est retiré (tu restes sur le serveur public). Dès que tu repaies, l'accès revient automatiquement.`,
  },
  {
    q: "Comment annuler ?",
    a: "Depuis ton espace membre, bouton « Annuler le renouvellement ». Tu gardes l'accès jusqu'à la fin de la période déjà payée.",
  },
  {
    q: "J'ai déjà payé par WhatsApp ou par transfert Wave ?",
    a: "Contacte-nous sur WhatsApp avec ton pseudo Discord : ton paiement est validé manuellement et ton accès activé.",
  },
];

export default async function HomePage() {
  const launch = new Date(`${CLUB.launchDate}T12:00:00Z`);
  const db = getDeps().db;
  const [settings, catalog] = await Promise.all([getSettings(db), getCatalog(db)]);
  const prices = catalog.list.filter((p) => p.purchasable).map((p) => p.priceXof!);
  const fromPrice = prices.length ? Math.min(...prices) : null;
  const telegramUrl = telegramLinkFor(settings, { hasAccess: false });
  const posters = listPosters();
  const days = settings.schedule.days;
  return (
    <>
      <section className="hero" aria-labelledby="hero-title">
        <Candles className="hero-candles" />
        <div className="container hero-inner">
          <p className="label">V_ICT_ORIOUS · Live Club · Discord</p>
          <h1 id="hero-title" className="display">
            Live <span className="outline">Trading</span>
            <br />
            Club
          </h1>
          <div className="badges">
            <span className="badge">
              <span className="dot" aria-hidden="true" /> Démarrage officiel · lundi {formatDate(launch)}
            </span>
            <span className="badge gold">1 invité spécial chaque semaine</span>
          </div>
          <p className="lead">
            Nasdaq et Gold en direct avec <strong>Victor Faye</strong>, Data Scientist et trader ICT. Trois lives par semaine pour
            apprendre en pratiquant : Live · Q&amp;A · Débrief.
          </p>
          <div className="actions">
            <a className="btn" href="#formules">
              Rejoindre le club
            </a>
            <a className="btn ghost" href="#planning">
              Voir le planning
            </a>
          </div>
          <p className="muted" style={{ margin: 0, fontSize: "0.9rem" }}>
            {fromPrice !== null ? `À partir de ${formatXof(fromPrice)} · Mobile Money ou carte` : "Tarifs en FCFA bientôt disponibles · Mobile Money ou carte"}
          </p>
        </div>
      </section>

      <section id="planning" className="section" aria-labelledby="planning-title">
        <div className="container">
          <div className="section-head">
            <p className="label">Planning hebdomadaire</p>
            <h2 id="planning-title" className="display">
              {days.length} lives <span className="accent">par semaine</span>
            </h2>
            <p className="lead">{settings.schedule.note ?? (days.some((d) => d.time) ? "Heure de Dakar (GMT)." : "Horaires précis annoncés très bientôt.")}</p>
          </div>
          <div className="days" style={{ gridTemplateColumns: `repeat(${Math.min(days.length, 4)}, 1fr)` }}>
            {days.map((d) => (
              <div key={d.day} className="card day">
                <p className="display">{d.day}</p>
                <p className="label">{settings.schedule.format}</p>
                <p className="day-time">
                  {d.time ?? "Horaire à venir"}
                  <span className="sr-only"> le {WEEK_DAYS.find((w) => w.day === d.day)!.label.toLowerCase()}</span>
                </p>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section id="avantages" className="section" aria-labelledby="avantages-title">
        <div className="container">
          <div className="section-head">
            <p className="label">Ce que tu obtiens</p>
            <h2 id="avantages-title" className="display">
              6 avantages <span className="accent">membres</span>
            </h2>
          </div>
          <div className="grid grid-3">
            {ADVANTAGES.map((a, i) => (
              <article key={a.title} className="card">
                <span className="num">{String(i + 1).padStart(2, "0")}</span>
                <h3 className="display">{a.title}</h3>
                <p>{a.text}</p>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section className="section gold-zone" aria-labelledby="gold-title">
        <Candles color="#f2b732" className="hero-candles" />
        <div className="container">
          <div className="section-head">
            <p className="label gold">Exclusivité membres · XAUUSD</p>
            <h2 id="gold-title" className="display gold-text">Stratégies Gold</h2>
            <p className="lead">Deux stratégies sur l'or, développées et backtestées par Victor, réservées aux membres du club.</p>
          </div>
          <div className="grid grid-2">
            <article className="card gold">
              <span className="num">Stratégie 01</span>
              <h3 className="display">Le 6-7 Range</h3>
              <p>Stratégie Gold développée et backtestée par Victor. Le détail est réservé aux membres.</p>
            </article>
            <article className="card gold">
              <span className="num">Stratégie 02</span>
              <h3 className="display">Swing Victorious</h3>
              <p>Stratégie swing sur XAUUSD, développée et backtestée par Victor. Le détail est réservé aux membres.</p>
            </article>
          </div>
          <p className="note" style={{ borderColor: "var(--gold-line)" }}>
            Bientôt : signaux swing Gold pour les membres.
          </p>
        </div>
      </section>

      <section className="section" aria-labelledby="canaux-title">
        <div className="container">
          <div className="section-head">
            <p className="label">Où ça se passe</p>
            <h2 id="canaux-title" className="display">
              Lives sur Discord, <span className="accent">reviews sur Telegram</span>
            </h2>
          </div>
          <div className="grid grid-2">
            <article className="card">
              <span className="num">Discord</span>
              <h3 className="display">Les lives</h3>
              <p>Les lives, le Q&amp;A et les échanges avec les invités se passent dans les salons privés du serveur.</p>
            </article>
            <article className="card">
              <span className="num">Telegram</span>
              <h3 className="display">Les reviews</h3>
              <p>Groupe « ICT V_ICT_orious Trader » : enregistrements des sessions, cours, support et débriefing complet après chaque live.</p>
            </article>
          </div>
          {telegramUrl ? (
            <div className="actions" style={{ marginTop: 20 }}>
              <TelegramButton url={telegramUrl} />
            </div>
          ) : null}
        </div>
      </section>

      <section id="formules" className="section" aria-labelledby="formules-title">
        <div className="container">
          <div className="section-head">
            <p className="label">Formules</p>
            <h2 id="formules-title" className="display">
              Rejoins <span className="accent">le club</span>
            </h2>
          </div>
          <PlanCards plans={catalog.list} days={days.map((d) => d.day)} />
          <p className="note">
            <strong>Carte bancaire :</strong> renouvellement automatique, uniquement avec ton accord explicite, annulable à tout moment.{" "}
            <strong>Mobile Money :</strong> renouvellement par rappel (J-3, J-1, J0) avec un lien de paiement en 1 clic. Les prix en dollars
            sont indicatifs : le paiement se fait en FCFA.
          </p>
        </div>
      </section>

      {posters.length ? (
        <section className="section" aria-labelledby="affiches-title">
          <div className="container">
            <div className="section-head">
              <p className="label">Le Live Club en images</p>
              <h2 id="affiches-title" className="display">
                Les <span className="accent">affiches</span>
              </h2>
            </div>
            <div className="posters">
              {posters.map((p) => (
                <a key={p.src} href={p.src} target="_blank" rel="noopener noreferrer" className="poster">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img src={p.src} alt={p.alt} loading="lazy" decoding="async" />
                </a>
              ))}
            </div>
          </div>
        </section>
      ) : null}

      <section id="faq" className="section" aria-labelledby="faq-title">
        <div className="container">
          <div className="section-head">
            <p className="label">Questions fréquentes</p>
            <h2 id="faq-title" className="display">FAQ</h2>
          </div>
          <div className="faq">
            {FAQ.map((item) => (
              <details key={item.q}>
                <summary>{item.q}</summary>
                <div>{item.a}</div>
              </details>
            ))}
          </div>
        </div>
      </section>

      <section id="contact" className="section" aria-labelledby="contact-title">
        <div className="container">
          <div className="section-head">
            <p className="label">Contact</p>
            <h2 id="contact-title" className="display">
              Une question ? <span className="accent">WhatsApp</span>
            </h2>
            <p className="lead">Écris-nous, on te répond rapidement.</p>
          </div>
          <div className="actions">
            <a className="btn" href={`https://wa.me/${CLUB.whatsappNumber.replace("+", "")}`} rel="noopener noreferrer">
              WhatsApp · {CLUB.whatsappDisplay}
            </a>
            <Link className="btn ghost" href="/inscription">
              S'inscrire
            </Link>
          </div>
        </div>
      </section>
    </>
  );
}
