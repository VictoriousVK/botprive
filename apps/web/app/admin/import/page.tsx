import type { Metadata } from "next";
import { getSettings } from "@vk/core";
import { AdminDenied, AdminPage } from "@/components/admin";
import { ImportTool } from "@/components/ImportTool";
import { getAdmin } from "@/lib/admin";
import { getCurrentMember, getDeps } from "@/lib/server";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Import CSV", robots: { index: false } };

export default async function ImportPage() {
  const admin = await getAdmin();
  if (!admin) return <AdminDenied loggedIn={Boolean(await getCurrentMember())} />;
  const { discordSync } = await getSettings(getDeps().db);
  return (
    <AdminPage
      title="Import des membres actuels"
      intro="Tes membres actuels gardent leur date de fin, sans repayer. Le fichier est d'abord vérifié ligne par ligne (identifiant Discord, formule, date, présence sur le serveur) ; rien n'est écrit avant ta confirmation."
    >
      <ImportTool discordMode={discordSync.mode} />
    </AdminPage>
  );
}
