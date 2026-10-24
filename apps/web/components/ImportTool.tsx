"use client";

import { useState } from "react";

interface PreviewRow {
  line: number;
  discordUserId: string;
  name: string | null;
  planId: string | null;
  endDate: string | null;
  level: "ok" | "warning" | "error" | "skip";
  messages: string[];
  discord: "present" | "absent" | "unverified";
  resultingStatus: string | null;
}

interface Preview {
  rows: PreviewRow[];
  summary: { total: number; importable: number; warnings: number; errors: number; skipped: number };
}

const LEVEL = { ok: "OK", warning: "À vérifier", error: "Rejetée", skip: "Ignorée" } as const;
const DISCORD = { present: "sur le serveur", absent: "absent", unverified: "non vérifié" } as const;
const PLAN = { monthly: "Mensuel", quarterly: "Trimestriel", annual: "Annuel" } as Record<string, string>;
const STATUS: Record<string, string> = {
  active: "Actif",
  renewal_due: "Renouvellement proche",
  grace_period: "Période de grâce",
  expired: "Expiré",
};

/** Import en deux temps : aperçu (rien n'est écrit), puis import confirmé. */
export function ImportTool({ discordMode }: { discordMode: "observe" | "live" }) {
  const [csv, setCsv] = useState<string>("");
  const [fileName, setFileName] = useState<string>("");
  const [preview, setPreview] = useState<Preview | null>(null);
  const [result, setResult] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function onFile(file: File | undefined) {
    setPreview(null);
    setResult(null);
    setError(null);
    if (!file) return;
    if (file.size > 1_000_000) return setError("Fichier trop volumineux (1 Mo maximum).");
    setFileName(file.name);
    setCsv(await file.text());
  }

  async function call(path: string, body: unknown) {
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(path, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
      const data = await res.json().catch(() => ({ error: `Erreur HTTP ${res.status}` }));
      if (!res.ok) throw new Error(data.error ?? `Erreur HTTP ${res.status}`);
      return data;
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      return null;
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="stack">
      <div className="field">
        <label htmlFor="csv">Fichier CSV des membres</label>
        <input id="csv" type="file" accept=".csv,text/csv" onChange={(e) => onFile(e.target.files?.[0])} />
        <small>
          Colonnes : discord_user_id, nom, email, téléphone, formule, date_de_fin. <a href="/api/admin/import/template">Télécharger le modèle</a> ·{" "}
          <a href="/api/admin/import/role-holders">Exporter les détenteurs actuels du rôle abonné</a> (identifiants pré-remplis, formule et date à compléter)
        </small>
      </div>
      <div className="actions">
        <button
          className="btn"
          type="button"
          disabled={!csv || busy}
          onClick={async () => {
            const data = await call("/api/admin/import/preview", { csv });
            if (data) setPreview(data as Preview);
          }}
        >
          {busy && !preview ? "Vérification…" : "Vérifier le fichier"}
        </button>
      </div>
      {error ? <p className="alert error" role="alert">{error}</p> : null}

      {preview ? (
        <>
          <p className="alert" role="status">
            {fileName} : {preview.summary.total} ligne(s) · <strong>{preview.summary.importable} importable(s)</strong> dont {preview.summary.warnings} à vérifier ·{" "}
            {preview.summary.errors} rejetée(s) · {preview.summary.skipped} déjà enregistrée(s). Rien n'a encore été écrit.
          </p>
          <div className="table-wrap">
            <table>
              <thead>
                <tr><th>Ligne</th><th>Résultat</th><th>ID Discord</th><th>Nom</th><th>Formule</th><th>Fin</th><th>Statut importé</th><th>Discord</th><th>Remarques</th></tr>
              </thead>
              <tbody>
                {preview.rows.map((r) => (
                  <tr key={r.line} className={`row-${r.level}`}>
                    <td>{r.line}</td>
                    <td>{LEVEL[r.level]}</td>
                    <td><code>{r.discordUserId || "—"}</code></td>
                    <td>{r.name ?? "—"}</td>
                    <td>{r.planId ? PLAN[r.planId] : "—"}</td>
                    <td>{r.endDate ? new Date(r.endDate).toLocaleDateString("fr-FR", { timeZone: "Africa/Dakar" }) : "—"}</td>
                    <td>{r.resultingStatus ? STATUS[r.resultingStatus] ?? r.resultingStatus : "—"}</td>
                    <td>{DISCORD[r.discord]}</td>
                    <td className="wrap">{r.messages.join(" · ")}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="note">
            {discordMode === "observe"
              ? "Discord est en mode observation : l'import enregistre les abonnements mais ne modifie aucun rôle sur le serveur. Le salon de logs indiquera ce qui serait fait."
              : "Discord est en mode réel : après l'import, le bot attribue le rôle aux membres dont l'abonnement est actif."}
          </p>
          <div className="actions">
            <button
              className="btn"
              type="button"
              disabled={busy || preview.summary.importable === 0}
              onClick={async () => {
                const data = await call("/api/admin/import/apply", { csv, confirm: true });
                if (data) {
                  setResult(`${data.created} membre(s) importé(s), ${data.skipped} ignoré(s), ${data.errors.length} ligne(s) rejetée(s).`);
                  setPreview(null);
                }
              }}
            >
              Importer {preview.summary.importable} membre(s)
            </button>
          </div>
        </>
      ) : null}
      {result ? <p className="alert success" role="status">{result}</p> : null}
    </div>
  );
}
