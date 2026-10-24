import type { Metadata } from "next";
import Link from "next/link";
import { formatXof, hasActiveAutoRenewal, isPlanId, PLANS } from "@vk/core";
import { CheckoutForm } from "@/components/CheckoutForm";
import { errorMessage } from "@/lib/messages";
import { getCurrentMember, getDeps } from "@/lib/server";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Inscription" };

export default async function InscriptionPage({ searchParams }: { searchParams: Promise<{ plan?: string; erreur?: string }> }) {
  const sp = await searchParams;
  const planId = sp.plan && isPlanId(sp.plan) ? sp.plan : "quarterly";
  const error = errorMessage(sp.erreur);
  const member = await getCurrentMember();
  const deps = getDeps();

  if (!member) {
    const next = `/inscription?plan=${planId}`;
    return (
      <div className="container page page-narrow">
        <p className="label">Inscription · étape 1 sur 2</p>
        <h1 className="display" style={{ fontSize: "clamp(2.6rem, 11vw, 4.6rem)" }}>
          Connecte ton Discord
        </h1>
        {error ? <p className="alert error" role="alert">{error}</p> : null}
        <p className="lead">
          Ton accès aux lives est lié à ton compte Discord. La connexion nous permet d'identifier ton vrai compte et de t'ajouter au
          serveur si tu n'y es pas encore. Nous ne lisons pas tes messages.
        </p>
        <p className="muted">Formule choisie : {PLANS[planId].label} · {formatXof(PLANS[planId].priceXof)}</p>
        <a className="btn" href={`/api/auth/discord/login?next=${encodeURIComponent(next)}`}>
          Se connecter avec Discord
        </a>
        <p className="muted" style={{ marginTop: 24, fontSize: "0.9rem" }}>
          Pas encore de compte Discord ? Crée-le gratuitement sur discord.com puis reviens ici.
        </p>
      </div>
    );
  }

  const card = deps.providers.forMethod("card");
  const mobileMoney = deps.providers.forMethod("mobile_money");
  const autoActive = await hasActiveAutoRenewal(deps, member.id);
  const plans = Object.values(PLANS).map((p) => ({
    id: p.id,
    label: p.label,
    months: p.months,
    priceUsd: p.priceUsd,
    priceXofLabel: formatXof(p.priceXof),
    badge: p.badge,
  }));
  const autoRenewPlans =
    card?.capabilities.recurring && card.providerPlanIdFor ? plans.filter((p) => card.providerPlanIdFor!(p.id as never)).map((p) => p.id) : [];

  return (
    <div className="container page page-narrow">
      <p className="label">Inscription · étape 2 sur 2</p>
      <h1 className="display" style={{ fontSize: "clamp(2.6rem, 11vw, 4.6rem)" }}>
        Paiement
      </h1>
      <p className="muted">
        Connecté en tant que <strong>{member.discordUsername ?? member.discordUserId}</strong>.
      </p>
      {error ? <p className="alert error" role="alert">{error}</p> : null}
      {autoActive ? (
        <div className="alert">
          <p style={{ marginTop: 0 }}>
            Ton renouvellement automatique par carte est actif : ton abonnement sera prolongé à l'échéance sans action de ta part.
          </p>
          <Link className="btn small ghost" href="/espace">
            Gérer mon abonnement
          </Link>
        </div>
      ) : !card && !mobileMoney ? (
        <div className="alert">
          Le paiement en ligne ouvre très bientôt. En attendant, contacte-nous sur WhatsApp pour t'inscrire.
        </div>
      ) : (
        <CheckoutForm
          plans={plans}
          initialPlan={planId}
          email={member.email ?? ""}
          phone={member.phone ?? ""}
          card={Boolean(card)}
          mobileMoney={Boolean(mobileMoney)}
          mobileMoneyLabel={mobileMoney?.id === "wave" ? "Wave" : "Orange Money, Wave"}
          autoRenewPlans={autoRenewPlans}
        />
      )}
    </div>
  );
}
