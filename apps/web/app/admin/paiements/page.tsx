import type { Metadata } from "next";
import Link from "next/link";
import { formatDateTime, formatXof, getPlan, isPlanId, listPayments } from "@vk/core";
import { AdminDenied, AdminPage } from "@/components/admin";
import { getAdmin } from "@/lib/admin";
import { getCurrentMember, getDeps } from "@/lib/server";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Paiements", robots: { index: false } };

const STATUSES = ["", "pending", "succeeded", "failed", "refunded"] as const;

export default async function PaiementsPage({ searchParams }: { searchParams: Promise<{ statut?: string }> }) {
  const admin = await getAdmin();
  if (!admin) return <AdminDenied loggedIn={Boolean(await getCurrentMember())} />;
  const statut = (await searchParams).statut ?? "";
  const status = STATUSES.includes(statut as (typeof STATUSES)[number]) ? statut : "";
  const deps = getDeps();
  const rows = await listPayments(deps.db, { status: status || undefined, limit: 150 });
  return (
    <AdminPage title="Paiements" intro={deps.env.PAYMENT_MODE === "live" ? "Paiements réels." : "Mode test : aucun de ces paiements n'est un encaissement réel."}>
      <nav className="actions" style={{ marginBottom: 16 }} aria-label="Filtrer">
        {STATUSES.map((s) => (
          <Link key={s || "all"} className={`btn small ${s === status ? "" : "ghost"}`} href={s ? `/admin/paiements?statut=${s}` : "/admin/paiements"}>
            {s || "tous"}
          </Link>
        ))}
      </nav>
      <div className="table-wrap">
        <table>
          <thead><tr><th>Date</th><th>Membre</th><th>Formule</th><th>Montant</th><th>Prestataire</th><th>Statut</th><th>Référence</th></tr></thead>
          <tbody>
            {rows.map(({ payment: p, username, discordUserId }) => (
              <tr key={p.id}>
                <td>{formatDateTime(p.createdAt)}</td>
                <td><Link href={`/admin/membres/${p.memberId}`}>{username ?? discordUserId}</Link></td>
                <td>{isPlanId(p.planId) ? getPlan(p.planId).label : p.planId}</td>
                <td>{formatXof(p.amount)}</td>
                <td>{p.provider} · {p.method}{p.kind === "recurring" ? " · prélèvement" : ""}</td>
                <td>{p.status}</td>
                <td><code>{p.reference}</code></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {rows.length === 0 ? <p className="muted">Aucun paiement.</p> : null}
    </AdminPage>
  );
}
