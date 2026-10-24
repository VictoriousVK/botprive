import type { Metadata } from "next";
import { formatDateTime, formatXof, getCatalog, getSettings } from "@vk/core";
import { AdminDenied, AdminPage, Pill } from "@/components/admin";
import { getAdmin } from "@/lib/admin";
import { getCurrentMember, getDeps } from "@/lib/server";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Tarifs", robots: { index: false } };

export default async function TarifsPage() {
  const admin = await getAdmin();
  if (!admin) return <AdminDenied loggedIn={Boolean(await getCurrentMember())} />;
  const deps = getDeps();
  const [catalog, settings] = await Promise.all([getCatalog(deps.db), getSettings(deps.db)]);
  const flutterwave = deps.providers.has("flutterwave");

  return (
    <AdminPage
      title="Tarifs"
      intro={
        <>
          Les prix en FCFA sont ceux réellement encaissés. Une formule sans prix FCFA n'est pas proposée à l'achat. Chaque modification annule la
          validation : rien n'est encaissé en mode réel tant que tu n'as pas validé.
        </>
      }
    >
      <div style={{ marginBottom: 18 }}>
        {catalog.pricesValidated ? (
          <Pill tone="ok">Tarifs validés{settings.pricing.validatedAt ? ` le ${formatDateTime(new Date(settings.pricing.validatedAt))}` : ""}</Pill>
        ) : (
          <Pill tone="warn">Tarifs non validés</Pill>
        )}
      </div>

      <form method="post" action="/api/admin/plans" className="stack">
        <div className="grid grid-3">
          {catalog.list.map((p) => (
            <fieldset key={p.id}>
              <legend>
                {p.label} · {p.months} mois
              </legend>
              <label className="inline-check">
                <input type="checkbox" name={`${p.id}.enabled`} defaultChecked={p.enabled} /> Proposée à la vente
              </label>
              <div className="field">
                <label htmlFor={`${p.id}-xof`}>Prix encaissé (FCFA)</label>
                <input id={`${p.id}-xof`} name={`${p.id}.priceXof`} inputMode="numeric" placeholder="À définir" defaultValue={p.priceXof ?? ""} />
              </div>
              <div className="field">
                <label htmlFor={`${p.id}-usd`}>Prix affiché ($, indicatif)</label>
                <input id={`${p.id}-usd`} name={`${p.id}.priceUsd`} inputMode="numeric" defaultValue={p.priceUsd ?? ""} />
              </div>
              <div className="field">
                <label htmlFor={`${p.id}-badge`}>Badge (facultatif)</label>
                <input id={`${p.id}-badge`} name={`${p.id}.badge`} maxLength={40} defaultValue={p.badge ?? ""} />
              </div>
              <div className="field">
                <label htmlFor={`${p.id}-tagline`}>Accroche</label>
                <input id={`${p.id}-tagline`} name={`${p.id}.tagline`} maxLength={140} defaultValue={p.tagline} />
              </div>
              <div className="field">
                <label htmlFor={`${p.id}-flw`}>Plan Flutterwave (prélèvement auto)</label>
                <input id={`${p.id}-flw`} name={`${p.id}.flutterwavePlanId`} defaultValue={p.flutterwavePlanId ?? ""} placeholder="Aucun" />
                <small>Détaché automatiquement si le prix change (un plan garde son montant).</small>
              </div>
            </fieldset>
          ))}
        </div>
        <button className="btn" type="submit">
          Enregistrer les formules
        </button>
      </form>

      {flutterwave ? (
        <section className="card" style={{ marginTop: 24 }}>
          <h2 className="label">Plans de prélèvement automatique (Flutterwave{deps.providers.get("flutterwave").testMode ? ", mode test" : ""})</h2>
          <p className="muted">Crée le plan au prix actuel pour proposer le renouvellement automatique par carte. Le support du FCFA pour les plans est à confirmer en sandbox.</p>
          <div className="actions">
            {catalog.list
              .filter((p) => p.priceXof !== null && !p.flutterwavePlanId)
              .map((p) => (
                <form key={p.id} method="post" action="/api/admin/flutterwave-plan">
                  <input type="hidden" name="plan" value={p.id} />
                  <button className="btn small ghost" type="submit">
                    Créer le plan {p.label} ({formatXof(p.priceXof!)})
                  </button>
                </form>
              ))}
          </div>
        </section>
      ) : null}

      <section className="card" style={{ marginTop: 24 }}>
        <h2 className="label">Validation</h2>
        {catalog.pricesValidated ? (
          <form method="post" action="/api/admin/pricing">
            <input type="hidden" name="action" value="unvalidate" />
            <button className="btn small ghost" type="submit">
              Annuler la validation
            </button>
          </form>
        ) : (
          <form method="post" action="/api/admin/pricing" className="stack">
            <ul style={{ margin: 0, paddingLeft: 18 }}>
              {catalog.list.map((p) => (
                <li key={p.id}>
                  {p.label} : {p.enabled ? (p.priceXof !== null ? formatXof(p.priceXof) : "prix manquant") : "non proposée"}
                </li>
              ))}
            </ul>
            <label className="inline-check">
              <input type="checkbox" name="confirm" /> Je confirme ces montants (ils seront encaissés en mode réel).
            </label>
            <button className="btn" type="submit">
              Valider les tarifs
            </button>
          </form>
        )}
      </section>
    </AdminPage>
  );
}
