import type { Metadata } from "next";
import { getSettings } from "@vk/core";
import { AdminDenied, AdminPage, Pill } from "@/components/admin";
import { getAdmin } from "@/lib/admin";
import { getCurrentMember, getDeps } from "@/lib/server";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Discord", robots: { index: false } };

export default async function DiscordPage() {
  const admin = await getAdmin();
  if (!admin) return <AdminDenied loggedIn={Boolean(await getCurrentMember())} />;
  const deps = getDeps();
  const { discordSync } = await getSettings(deps.db);
  const observe = discordSync.mode === "observe";
  return (
    <AdminPage
      title="Rôles Discord"
      intro="Par sécurité, le bot démarre en mode observation : il calcule ce qu'il ferait (attribution, retrait, messages privés et emails) et le journalise, sans rien modifier pour tes membres réels."
    >
      <p>{observe ? <Pill tone="warn">Observation : aucun accès réel modifié</Pill> : <Pill tone="ok">Rôles appliqués réellement</Pill>}</p>
      <form method="post" action="/api/admin/discord" className="stack">
        <fieldset>
          <legend>Mode</legend>
          <label className="choice">
            <input type="radio" name="mode" value="observe" defaultChecked={observe} />
            <span>
              <strong>Observation (recommandé pendant les tests)</strong>
              <small>Rien n'est modifié sur le serveur. Le salon de logs indique ce qui aurait été fait. Les membres réels ne reçoivent aucun message.</small>
            </span>
          </label>
          <label className="choice">
            <input type="radio" name="mode" value="live" defaultChecked={!observe} />
            <span>
              <strong>Réel</strong>
              <small>Le bot attribue et retire le rôle abonné et envoie rappels et messages. À activer après l'import de tes membres actuels.</small>
            </span>
          </label>
          {observe ? (
            <div className="field">
              <label htmlFor="confirm">Pour passer en réel, tape ACTIVER</label>
              <input id="confirm" name="confirm" autoComplete="off" placeholder="ACTIVER" />
            </div>
          ) : null}
        </fieldset>
        <div className="field">
          <label htmlFor="testUserIds">Comptes de test (actions réelles même en observation)</label>
          <textarea id="testUserIds" name="testUserIds" rows={3} defaultValue={discordSync.testUserIds.join("\n")} placeholder="Un identifiant Discord par ligne" />
          <small>Ex : ton compte secondaire, pour vérifier l'attribution du rôle et la réception des messages.</small>
        </div>
        <button className="btn" type="submit">
          Enregistrer
        </button>
      </form>
      <section className="card" style={{ marginTop: 24 }}>
        <h2 className="label">Exceptions permanentes (variables d'environnement)</h2>
        <p className="muted">Jamais touchés, quel que soit le mode : rôle admin, rôles et membres listés dans DISCORD_EXEMPT_ROLE_IDS et DISCORD_EXEMPT_USER_IDS, bots.</p>
        <p>
          Rôles : {[deps.env.DISCORD_ADMIN_ROLE_ID, ...deps.env.DISCORD_EXEMPT_ROLE_IDS].filter(Boolean).join(", ") || "—"} · Membres :{" "}
          {deps.env.DISCORD_EXEMPT_USER_IDS.join(", ") || "—"}
        </p>
      </section>
    </AdminPage>
  );
}
