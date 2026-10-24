import type { Metadata } from "next";
import { getSettings } from "@vk/core";
import { AdminDenied, AdminPage } from "@/components/admin";
import { getAdmin } from "@/lib/admin";
import { getCurrentMember, getDeps } from "@/lib/server";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Telegram", robots: { index: false } };

export default async function TelegramPage() {
  const admin = await getAdmin();
  if (!admin) return <AdminDenied loggedIn={Boolean(await getCurrentMember())} />;
  const { telegram } = await getSettings(getDeps().db);
  return (
    <AdminPage title="Groupe Telegram" intro="Bouton « Rejoindre notre groupe Telegram » du site, de l'espace membre et du message de bienvenue.">
      <form method="post" action="/api/admin/telegram" className="stack">
        <div className="field">
          <label htmlFor="url">Lien d'invitation</label>
          <input id="url" name="url" type="url" placeholder="https://t.me/+…" defaultValue={telegram.url ?? ""} />
          <small>Vide = bouton masqué partout.</small>
        </div>
        <fieldset>
          <legend>Qui voit le lien ?</legend>
          <label className="choice">
            <input type="radio" name="visibility" value="public" defaultChecked={telegram.visibility === "public"} />
            <span>
              <strong>Public</strong>
              <small>Page d'accueil, espace membre et messages. Toute personne qui visite le site peut rejoindre le groupe.</small>
            </span>
          </label>
          <label className="choice">
            <input type="radio" name="visibility" value="members" defaultChecked={telegram.visibility === "members"} />
            <span>
              <strong>Membres actifs uniquement</strong>
              <small>Visible seulement dans l'espace membre des abonnés actifs et dans leur message de bienvenue.</small>
            </span>
          </label>
        </fieldset>
        <p className="note">
          Le groupe partage les enregistrements des sessions : en mode public, ces replays deviennent accessibles hors abonnement. Pour un lien déjà
          diffusé, tu peux en générer un nouveau dans Telegram (Gérer le groupe → Liens d'invitation) et le remplacer ici.
        </p>
        <button className="btn" type="submit">
          Enregistrer
        </button>
      </form>
    </AdminPage>
  );
}
