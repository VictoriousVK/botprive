import type { Metadata } from "next";
import { formatDate, formatXof, getMember, getSubscriptionForMember, hasActiveAutoRenewal, PLANS, signingSecret, verifyRenewalToken } from "@vk/core";
import { errorMessage } from "@/lib/messages";
import { getDeps } from "@/lib/server";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Renouvellement", robots: { index: false } };

/** Lien pré-rempli envoyé dans les rappels : paiement en 1 clic, sans connexion. */
export default async function RenewPage({ params, searchParams }: { params: Promise<{ token: string }>; searchParams: Promise<{ erreur?: string }> }) {
  const { token } = await params;
  const sp = await searchParams;
  const deps = getDeps();
  const claims = verifyRenewalToken(signingSecret(deps.env), decodeURIComponent(token), deps.now());
  const member = claims ? await getMember(deps.db, claims.memberId) : null;

  if (!claims || !member) {
    return (
      <div className="container page page-narrow">
        <p className="label">Renouvellement</p>
        <h1 className="display" style={{ fontSize: "clamp(2.4rem, 10vw, 4rem)" }}>Lien expiré</h1>
        <p className="lead">Ce lien n'est plus valable. Connecte-toi à ton espace pour renouveler.</p>
        <a className="btn" href="/espace">Mon espace</a>
      </div>
    );
  }

  const plan = PLANS[claims.planId];
  const sub = await getSubscriptionForMember(deps.db, member.id);
  const autoActive = await hasActiveAutoRenewal(deps, member.id);
  const mobileMoney = deps.providers.forMethod("mobile_money");
  const card = deps.providers.forMethod("card");
  const error = errorMessage(sp.erreur);

  return (
    <div className="container page page-narrow">
      <p className="label">Renouvellement en 1 clic</p>
      <h1 className="display" style={{ fontSize: "clamp(2.4rem, 10vw, 4rem)" }}>
        {plan.label} · {formatXof(plan.priceXof)}
      </h1>
      <p className="lead">
        Compte Discord : <strong>{member.discordUsername ?? member.discordUserId}</strong>
        {sub?.currentPeriodEnd ? (
          <>
            <br />
            Accès actuel jusqu'au {formatDate(sub.currentPeriodEnd)}. La nouvelle période démarre à la fin de l'actuelle.
          </>
        ) : null}
      </p>
      {error ? <p className="alert error" role="alert">{error}</p> : null}
      {autoActive ? (
        <p className="alert">Ton renouvellement automatique par carte est actif : rien à faire, il sera prélevé à l'échéance.</p>
      ) : (
        <div className="grid" style={{ gap: 12 }}>
          {mobileMoney ? (
            <form method="post" action="/api/renew">
              <input type="hidden" name="token" value={decodeURIComponent(token)} />
              <input type="hidden" name="method" value="mobile_money" />
              <button className="btn block" type="submit">
                Payer {formatXof(plan.priceXof)} · Mobile Money
              </button>
            </form>
          ) : null}
          {card ? (
            <form method="post" action="/api/renew">
              <input type="hidden" name="token" value={decodeURIComponent(token)} />
              <input type="hidden" name="method" value="card" />
              <button className="btn block ghost" type="submit">
                Payer par carte (sans renouvellement automatique)
              </button>
            </form>
          ) : null}
          <p className="muted" style={{ fontSize: "0.88rem" }}>
            Changer de formule ou activer le renouvellement automatique : <a href={`/inscription?plan=${plan.id}`}>page d'inscription</a>.
          </p>
        </div>
      )}
    </div>
  );
}
