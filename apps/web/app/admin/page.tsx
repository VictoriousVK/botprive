import type { Metadata } from "next";
import Link from "next/link";
import { formatDate, formatDateTime, formatXof, getCatalog, getSettings, getStats, listAudit, listExpiring, listPayments, STATUS_LABELS, type SubscriptionStatus } from "@vk/core";
import { AdminDenied, AdminPage, Pill } from "@/components/admin";
import { getAdmin } from "@/lib/admin";
import { getCurrentMember, getDeps } from "@/lib/server";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Administration", robots: { index: false } };

export default async function AdminHome() {
  const admin = await getAdmin();
  if (!admin) return <AdminDenied loggedIn={Boolean(await getCurrentMember())} />;
  const deps = getDeps();
  const now = deps.now();
  const [settings, catalog, stats, expiring, lastPayments, lastAudit] = await Promise.all([
    getSettings(deps.db),
    getCatalog(deps.db),
    getStats(deps.db, now),
    listExpiring(deps.db, now, 7),
    listPayments(deps.db, { limit: 8 }),
    listAudit(deps.db, { limit: 8 }),
  ]);
  const live = deps.env.PAYMENT_MODE === "live";
  const missingPrices = catalog.list.filter((p) => p.enabled && p.priceXof === null);
  const alerts: string[] = [];
  if (missingPrices.length) alerts.push(`Prix FCFA à définir : ${missingPrices.map((p) => p.label).join(", ")} (les formules sans prix ne sont pas achetables).`);
  if (!catalog.pricesValidated) alerts.push("Tarifs non validés : aucun encaissement réel ne sera possible en mode live.");
  if (live && settings.discordSync.mode === "observe") alerts.push("Paiements réels activés mais rôles Discord en observation : les abonnés ne recevront pas leur rôle.");
  if (settings.telegram.url && settings.telegram.visibility === "public") alerts.push("Lien Telegram public : toute personne qui visite le site peut rejoindre le groupe (et voir les replays).");
  for (const d of deps.providers.disabled) alerts.push(`Prestataire ${d.id} écarté : ${d.reason}.`);
  if (deps.providers.all().length === 0) alerts.push("Aucun prestataire de paiement actif : configure des clés de test (voir docs/guide-paiements.md).");

  return (
    <AdminPage title="Vue d'ensemble">
      <div className="kpis">
        <div className="card kpi">
          <p className="label">Paiements</p>
          <div style={{ marginTop: 10 }}>{live ? <Pill tone="ok">Réels</Pill> : <Pill tone="warn">Mode test</Pill>}</div>
          <p className="muted" style={{ fontSize: "0.85rem", marginTop: 8 }}>
            {deps.providers.all().map((p) => `${p.id}${p.testMode ? " (test)" : ""}`).join(", ") || "aucun prestataire"}
          </p>
        </div>
        <div className="card kpi">
          <p className="label">Rôles Discord</p>
          <div style={{ marginTop: 10 }}>{settings.discordSync.mode === "live" ? <Pill tone="ok">Appliqués</Pill> : <Pill tone="warn">Observation</Pill>}</div>
          <p className="muted" style={{ fontSize: "0.85rem", marginTop: 8 }}>
            {settings.discordSync.testUserIds.length} compte(s) de test · <Link href="/admin/discord">régler</Link>
          </p>
        </div>
        <div className="card kpi">
          <p className="label">Membres avec accès</p>
          <p className="value">{stats.withAccess}</p>
          <p className="muted" style={{ fontSize: "0.85rem" }}>dont {stats.autoRenew} en prélèvement auto</p>
        </div>
        <div className="card kpi">
          <p className="label">Encaissé 30 j</p>
          <p className="value">{formatXof(stats.revenue30d)}</p>
          <p className="muted" style={{ fontSize: "0.85rem" }}>{stats.payments30d} paiement(s){live ? "" : " · test"}</p>
        </div>
      </div>

      {alerts.length ? (
        <section className="card" style={{ marginTop: 20 }} aria-labelledby="alertes">
          <h2 id="alertes" className="label">À traiter</h2>
          <ul style={{ margin: "12px 0 0", paddingLeft: 18, display: "grid", gap: 8 }}>
            {alerts.map((a) => (
              <li key={a}>{a}</li>
            ))}
          </ul>
        </section>
      ) : null}

      <div className="grid grid-2" style={{ marginTop: 20 }}>
        <section className="card" aria-labelledby="echeances">
          <h2 id="echeances" className="label">Échéances des 7 prochains jours</h2>
          {expiring.length === 0 ? (
            <p className="muted" style={{ marginTop: 12 }}>Aucune.</p>
          ) : (
            <ul style={{ margin: "12px 0 0", paddingLeft: 18, display: "grid", gap: 6 }}>
              {expiring.slice(0, 12).map((r) => (
                <li key={r.discordUserId}>
                  {r.username ?? r.discordUserId} · {r.currentPeriodEnd ? formatDate(r.currentPeriodEnd) : "—"} · {STATUS_LABELS[r.status as SubscriptionStatus]}
                </li>
              ))}
            </ul>
          )}
        </section>
        <section className="card" aria-labelledby="derniers">
          <h2 id="derniers" className="label">Derniers paiements</h2>
          {lastPayments.length === 0 ? (
            <p className="muted" style={{ marginTop: 12 }}>Aucun.</p>
          ) : (
            <ul style={{ margin: "12px 0 0", paddingLeft: 18, display: "grid", gap: 6 }}>
              {lastPayments.map(({ payment, username, discordUserId }) => (
                <li key={payment.id}>
                  {formatDateTime(payment.createdAt)} · {username ?? discordUserId} · {formatXof(payment.amount)} · {payment.provider} · {payment.status}
                </li>
              ))}
            </ul>
          )}
        </section>
      </div>

      <section className="card" style={{ marginTop: 20 }} aria-labelledby="actions">
        <h2 id="actions" className="label">Dernières actions</h2>
        <ul style={{ margin: "12px 0 0", paddingLeft: 18, display: "grid", gap: 6 }}>
          {lastAudit.map((a) => (
            <li key={a.id}>
              {formatDateTime(a.createdAt)} · {a.action} · {a.actorType}
              {a.actorId ? ` (${a.actorId})` : ""}
            </li>
          ))}
        </ul>
        <p style={{ marginTop: 12 }}>
          <Link href="/admin/journal">Tout le journal</Link>
        </p>
      </section>
    </AdminPage>
  );
}
