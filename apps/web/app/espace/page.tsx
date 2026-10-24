import type { Metadata } from "next";
import Link from "next/link";
import {
  formatDate,
  formatXof,
  getMemberDashboard,
  getPlan,
  hasAccess,
  isPlanId,
  type SubscriptionStatus,
} from "@vk/core";
import { StatusBadge } from "@/components/StatusBadge";
import { errorMessage } from "@/lib/messages";
import { getCurrentMember, getDeps } from "@/lib/server";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Espace membre" };

const PAYMENT_STATUS: Record<string, string> = {
  pending: "En attente",
  succeeded: "Payé",
  failed: "Échoué",
  refunded: "Remboursé",
};

const METHOD: Record<string, string> = { card: "Carte", mobile_money: "Mobile Money", manual: "Manuel" };

export default async function EspacePage({ searchParams }: { searchParams: Promise<{ erreur?: string; ok?: string }> }) {
  const sp = await searchParams;
  const member = await getCurrentMember();
  if (!member) {
    return (
      <div className="container page page-narrow">
        <p className="label">Espace membre</p>
        <h1 className="display" style={{ fontSize: "clamp(2.6rem, 11vw, 4.6rem)" }}>
          Connexion
        </h1>
        {errorMessage(sp.erreur) ? <p className="alert error" role="alert">{errorMessage(sp.erreur)}</p> : null}
        <p className="lead">Connecte-toi avec Discord pour voir ton abonnement, ton échéance et ton historique.</p>
        <a className="btn" href="/api/auth/discord/login?next=%2Fespace">
          Se connecter avec Discord
        </a>
      </div>
    );
  }

  const deps = getDeps();
  const data = await getMemberDashboard(deps.db, member.id);
  const sub = data?.subscription ?? null;
  const status = (sub?.status ?? null) as SubscriptionStatus | null;
  const plan = sub && isPlanId(sub.planId) ? getPlan(sub.planId) : null;
  const autoActive = sub?.renewalMode === "auto_card" && status !== "canceled" && hasAccess(status);
  const cancelable = status === "active" || status === "renewal_due" || (status === "grace_period" && sub?.renewalMode === "auto_card");
  const error = errorMessage(sp.erreur);

  return (
    <div className="container page">
      <p className="label">Espace membre</p>
      <h1 className="display" style={{ fontSize: "clamp(2.6rem, 11vw, 4.6rem)" }}>
        {member.discordUsername ?? "Mon abonnement"}
      </h1>
      {error ? <p className="alert error" role="alert">{error}</p> : null}
      {sp.ok === "annule" ? (
        <p className="alert success" role="status">
          Renouvellement annulé. Tu gardes l'accès jusqu'à la fin de la période payée.
        </p>
      ) : null}

      <div className="grid grid-2" style={{ marginTop: 24 }}>
        <section className="card" aria-labelledby="abo-title">
          <h2 id="abo-title" className="label">Mon abonnement</h2>
          <div style={{ margin: "16px 0" }}>
            <StatusBadge status={status} />
          </div>
          <dl className="kv">
            <div>
              <dt>Formule</dt>
              <dd>{plan ? `${plan.label} · ${formatXof(plan.priceXof)}` : "—"}</dd>
            </div>
            <div>
              <dt>{status === "expired" ? "Accès terminé le" : "Accès jusqu'au"}</dt>
              <dd>{sub?.currentPeriodEnd ? formatDate(status === "grace_period" && sub.graceEndsAt ? sub.graceEndsAt : sub.currentPeriodEnd) : "—"}</dd>
            </div>
            <div>
              <dt>Renouvellement</dt>
              <dd>
                {!sub || !hasAccess(status)
                  ? "—"
                  : status === "canceled"
                    ? "Annulé (pas de renouvellement)"
                    : autoActive
                      ? `Automatique par carte le ${sub.currentPeriodEnd ? formatDate(sub.currentPeriodEnd) : "—"}`
                      : "Par rappel (J-3, J-1, J0)"}
              </dd>
            </div>
          </dl>
          <div className="actions" style={{ marginTop: 22 }}>
            {autoActive ? null : (
              <Link className="btn" href={`/inscription?plan=${plan?.id ?? "quarterly"}`}>
                {hasAccess(status) ? "Renouveler" : "S'abonner"}
              </Link>
            )}
            {cancelable ? (
              <form method="post" action="/api/me/cancel-renewal">
                <button className="btn danger" type="submit">
                  Annuler le renouvellement
                </button>
              </form>
            ) : null}
          </div>
          {autoActive ? (
            <p className="muted" style={{ fontSize: "0.88rem" }}>
              Ton prélèvement par carte est actif : pas besoin de renouveler manuellement (cela créerait un double paiement).
            </p>
          ) : null}
        </section>

        <section className="card" aria-labelledby="acces-title">
          <h2 id="acces-title" className="label">Accès</h2>
          <ul style={{ margin: "16px 0 0", paddingLeft: 18, display: "grid", gap: 10 }}>
            <li>
              Serveur Discord : <a href={deps.env.DISCORD_INVITE_URL} rel="noopener noreferrer">rejoindre le serveur</a>
            </li>
            <li>
              Rôle membre : {hasAccess(status) ? "attribué automatiquement" : "attribué dès la confirmation de ton paiement"}
            </li>
            {hasAccess(status) && deps.env.TELEGRAM_INVITE_URL ? (
              <li>
                Telegram privé : <a href={deps.env.TELEGRAM_INVITE_URL} rel="noopener noreferrer">ICT V_ICT_orious Trader</a>
              </li>
            ) : null}
          </ul>
          <form method="post" action="/api/auth/logout" style={{ marginTop: 22 }}>
            <button className="btn small ghost" type="submit">
              Se déconnecter
            </button>
          </form>
        </section>
      </div>

      <section style={{ marginTop: 32 }} aria-labelledby="hist-title">
        <h2 id="hist-title" className="label" style={{ marginBottom: 12 }}>
          Historique des paiements
        </h2>
        {data?.history.length ? (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th scope="col">Date</th>
                  <th scope="col">Formule</th>
                  <th scope="col">Montant</th>
                  <th scope="col">Moyen</th>
                  <th scope="col">Statut</th>
                  <th scope="col">Référence</th>
                </tr>
              </thead>
              <tbody>
                {data.history.map((p) => (
                  <tr key={p.id}>
                    <td>{formatDate(p.confirmedAt ?? p.createdAt)}</td>
                    <td>{isPlanId(p.planId) ? getPlan(p.planId).label : p.planId}</td>
                    <td>{formatXof(p.amount)}</td>
                    <td>{METHOD[p.method] ?? p.method}</td>
                    <td>{PAYMENT_STATUS[p.status] ?? p.status}</td>
                    <td>
                      <code>{p.reference}</code>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <p className="muted">Aucun paiement pour le moment.</p>
        )}
      </section>
    </div>
  );
}
