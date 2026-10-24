import type { Metadata } from "next";
import Link from "next/link";
import { formatDate, getPlan, isPlanId, searchMembers, type SubscriptionStatus } from "@vk/core";
import { AdminDenied, AdminPage } from "@/components/admin";
import { StatusBadge } from "@/components/StatusBadge";
import { getAdmin } from "@/lib/admin";
import { getCurrentMember, getDeps } from "@/lib/server";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Membres", robots: { index: false } };

export default async function MembresPage({ searchParams }: { searchParams: Promise<{ q?: string }> }) {
  const admin = await getAdmin();
  if (!admin) return <AdminDenied loggedIn={Boolean(await getCurrentMember())} />;
  const q = ((await searchParams).q ?? "").slice(0, 100);
  const rows = await searchMembers(getDeps().db, q, 100);
  return (
    <AdminPage title="Membres" intro="Recherche par identifiant Discord, pseudo, nom, email ou référence de paiement. Pour ajouter ou retirer un accès : /ajouter et /retirer sur Discord.">
      <form method="get" className="actions" style={{ marginBottom: 16 }}>
        <div className="field" style={{ flex: 1, minWidth: 220 }}>
          <label htmlFor="q" className="label">
            Recherche
          </label>
          <input id="q" name="q" defaultValue={q} placeholder="ID Discord, pseudo, email, VK-…" />
        </div>
        <button className="btn" type="submit" style={{ alignSelf: "end" }}>
          Chercher
        </button>
      </form>
      <div className="table-wrap">
        <table>
          <thead>
            <tr>
              <th scope="col">Membre</th>
              <th scope="col">ID Discord</th>
              <th scope="col">Email</th>
              <th scope="col">Statut</th>
              <th scope="col">Formule</th>
              <th scope="col">Fin</th>
              <th scope="col">Renouvellement</th>
            </tr>
          </thead>
          <tbody>
            {rows.map(({ member, subscription }) => (
              <tr key={member.id}>
                <td>
                  <Link href={`/admin/membres/${member.id}`}>{member.discordUsername ?? member.name ?? "—"}</Link>
                </td>
                <td>
                  <code>{member.discordUserId}</code>
                </td>
                <td>{member.email ?? "—"}</td>
                <td>
                  <StatusBadge status={(subscription?.status ?? null) as SubscriptionStatus | null} />
                </td>
                <td>{subscription && isPlanId(subscription.planId) ? getPlan(subscription.planId).label : "—"}</td>
                <td>{subscription?.currentPeriodEnd ? formatDate(subscription.currentPeriodEnd) : "—"}</td>
                <td>{subscription ? (subscription.renewalMode === "auto_card" ? "Auto (carte)" : "Rappel") : "—"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {rows.length === 0 ? <p className="muted">Aucun membre trouvé.</p> : null}
    </AdminPage>
  );
}
