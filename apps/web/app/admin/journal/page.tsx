import type { Metadata } from "next";
import { formatDateTime, listAudit } from "@vk/core";
import { AdminDenied, AdminPage } from "@/components/admin";
import { getAdmin } from "@/lib/admin";
import { getCurrentMember, getDeps } from "@/lib/server";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Journal", robots: { index: false } };

export default async function JournalPage() {
  const admin = await getAdmin();
  if (!admin) return <AdminDenied loggedIn={Boolean(await getCurrentMember())} />;
  const rows = await listAudit(getDeps().db, { limit: 200 });
  return (
    <AdminPage title="Journal d'audit" intro="Les 200 dernières actions : paiements, rôles (réels ou simulés), commandes admin, réglages modifiés.">
      <div className="table-wrap">
        <table>
          <thead><tr><th>Date</th><th>Action</th><th>Par</th><th>Détails</th></tr></thead>
          <tbody>
            {rows.map((a) => (
              <tr key={a.id}>
                <td>{formatDateTime(a.createdAt)}</td>
                <td>{a.action}</td>
                <td>{a.actorType}{a.actorId ? ` (${a.actorId})` : ""}</td>
                <td className="wrap"><code style={{ fontSize: "0.75rem" }}>{a.details ? JSON.stringify(a.details).slice(0, 220) : ""}</code></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </AdminPage>
  );
}
