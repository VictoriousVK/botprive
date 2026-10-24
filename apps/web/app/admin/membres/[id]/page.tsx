import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { formatDate, formatDateTime, formatXof, getMemberDashboard, getPlan, isPlanId, listAudit, type SubscriptionStatus } from "@vk/core";
import { AdminDenied, AdminPage } from "@/components/admin";
import { StatusBadge } from "@/components/StatusBadge";
import { getAdmin } from "@/lib/admin";
import { getCurrentMember, getDeps } from "@/lib/server";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Fiche membre", robots: { index: false } };

export default async function MembrePage({ params }: { params: Promise<{ id: string }> }) {
  const admin = await getAdmin();
  if (!admin) return <AdminDenied loggedIn={Boolean(await getCurrentMember())} />;
  const { id } = await params;
  if (!/^[0-9a-f-]{36}$/.test(id)) notFound();
  const db = getDeps().db;
  const data = await getMemberDashboard(db, id);
  if (!data) notFound();
  const audit = await listAudit(db, { memberId: id, limit: 40 });
  const { member, subscription: sub } = data;
  return (
    <AdminPage title={member.discordUsername ?? member.name ?? "Membre"}>
      <div className="grid grid-2">
        <section className="card">
          <h2 className="label">Identité</h2>
          <dl className="kv" style={{ marginTop: 12 }}>
            <div><dt>ID Discord</dt><dd><code>{member.discordUserId}</code></dd></div>
            <div><dt>Nom</dt><dd>{member.name ?? "—"}</dd></div>
            <div><dt>Email</dt><dd>{member.email ?? "—"}{member.email ? (member.emailVerified ? " (vérifié par Discord)" : " (non vérifié)") : ""}</dd></div>
            <div><dt>Téléphone</dt><dd>{member.phone ?? "—"}</dd></div>
            <div><dt>Inscrit le</dt><dd>{formatDate(member.createdAt)}</dd></div>
          </dl>
        </section>
        <section className="card">
          <h2 className="label">Abonnement</h2>
          <div style={{ margin: "12px 0" }}>
            <StatusBadge status={(sub?.status ?? null) as SubscriptionStatus | null} />
          </div>
          <dl className="kv">
            <div><dt>Formule</dt><dd>{sub && isPlanId(sub.planId) ? getPlan(sub.planId).label : "—"}</dd></div>
            <div><dt>Période</dt><dd>{sub?.currentPeriodStart && sub.currentPeriodEnd ? `${formatDate(sub.currentPeriodStart)} → ${formatDate(sub.currentPeriodEnd)}` : "—"}</dd></div>
            <div><dt>Renouvellement</dt><dd>{sub ? (sub.renewalMode === "auto_card" ? `Auto carte (${sub.provider}, ${sub.recurringAmount ? formatXof(sub.recurringAmount) : "?"})` : "Rappel") : "—"}</dd></div>
          </dl>
        </section>
      </div>
      <h2 className="label" style={{ margin: "28px 0 12px" }}>Paiements</h2>
      <div className="table-wrap">
        <table>
          <thead><tr><th>Date</th><th>Référence</th><th>Montant</th><th>Prestataire</th><th>Statut</th><th>Détail</th></tr></thead>
          <tbody>
            {data.history.map((p) => (
              <tr key={p.id}>
                <td>{formatDateTime(p.createdAt)}</td>
                <td><code>{p.reference}</code></td>
                <td>{formatXof(p.amount)}</td>
                <td>{p.provider} · {p.method}{p.autoRenew ? " · auto" : ""}</td>
                <td>{p.status}</td>
                <td className="wrap">{p.failureReason ?? ""}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <h2 className="label" style={{ margin: "28px 0 12px" }}>Périodes</h2>
      <div className="table-wrap">
        <table>
          <thead><tr><th>Début</th><th>Fin</th><th>Origine</th><th>Note</th></tr></thead>
          <tbody>
            {data.periods.map((p) => (
              <tr key={p.id}><td>{formatDate(p.startsAt)}</td><td>{formatDate(p.endsAt)}</td><td>{p.source}{p.days ? ` · ${p.days} j` : ""}</td><td className="wrap">{p.note ?? ""}</td></tr>
            ))}
          </tbody>
        </table>
      </div>
      <h2 className="label" style={{ margin: "28px 0 12px" }}>Journal</h2>
      <div className="table-wrap">
        <table>
          <thead><tr><th>Date</th><th>Action</th><th>Par</th></tr></thead>
          <tbody>
            {audit.map((a) => (
              <tr key={a.id}><td>{formatDateTime(a.createdAt)}</td><td>{a.action}</td><td>{a.actorType}{a.actorId ? ` (${a.actorId})` : ""}</td></tr>
            ))}
          </tbody>
        </table>
      </div>
    </AdminPage>
  );
}
