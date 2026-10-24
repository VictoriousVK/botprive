import type { Metadata } from "next";
import { getSettings, WEEK_DAYS } from "@vk/core";
import { AdminDenied, AdminPage } from "@/components/admin";
import { getAdmin } from "@/lib/admin";
import { getCurrentMember, getDeps } from "@/lib/server";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Horaires des lives", robots: { index: false } };

export default async function LivesPage() {
  const admin = await getAdmin();
  if (!admin) return <AdminDenied loggedIn={Boolean(await getCurrentMember())} />;
  const { schedule } = await getSettings(getDeps().db);
  const byDay = new Map(schedule.days.map((d) => [d.day, d]));
  return (
    <AdminPage title="Horaires des lives" intro="Affichés sur le site et dans le message de bienvenue. Laisse l'horaire vide tant qu'il n'est pas fixé (« horaire à venir »).">
      <form method="post" action="/api/admin/schedule" className="stack">
        <fieldset>
          <legend>Jours et horaires</legend>
          {WEEK_DAYS.map((d) => {
            const current = byDay.get(d.day);
            return (
              <div key={d.day} className="form-grid cols-2" style={{ alignItems: "end" }}>
                <label className="inline-check">
                  <input type="checkbox" name={`${d.day}.enabled`} defaultChecked={Boolean(current)} /> {d.label}
                </label>
                <div className="field">
                  <label htmlFor={`${d.day}-time`}>Horaire ({d.label.toLowerCase()})</label>
                  <input id={`${d.day}-time`} name={`${d.day}.time`} placeholder="ex : 20h00 – 22h00 (GMT)" maxLength={60} defaultValue={current?.time ?? ""} />
                </div>
              </div>
            );
          })}
        </fieldset>
        <div className="form-grid cols-2">
          <div className="field">
            <label htmlFor="format">Format</label>
            <input id="format" name="format" maxLength={80} defaultValue={schedule.format} />
          </div>
          <div className="field">
            <label htmlFor="note">Note (facultatif)</label>
            <input id="note" name="note" maxLength={240} defaultValue={schedule.note ?? ""} placeholder="ex : heure de Dakar (GMT)" />
          </div>
        </div>
        <button className="btn" type="submit">
          Enregistrer les horaires
        </button>
      </form>
    </AdminPage>
  );
}
