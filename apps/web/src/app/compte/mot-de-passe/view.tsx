"use client";

import { KeyRound } from "lucide-react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useEffect, useState } from "react";
import { Notice, Spinner } from "@/components/ui";
import { api, type Me } from "@/lib/api";
import { useSession } from "@/lib/session";
import { PasswordField, strength } from "../auth";

// Landing page of the password reset link: /compte/mot-de-passe/?jeton=...
export function ResetView() {
  const params = useSearchParams();
  const [token] = useState(() => params.get("jeton") ?? "");
  const { setMe } = useSession();
  const router = useRouter();
  const [pw, setPw] = useState({ a: "", b: "" });
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [done, setDone] = useState(false);

  useEffect(() => {
    if (token) window.history.replaceState(null, "", "/compte/mot-de-passe/");
  }, [token]);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (pw.a !== pw.b) return setErr("Les deux mots de passe ne sont pas identiques.");
    setBusy(true);
    setErr(null);
    try {
      const r = await api<{ member: Me | null }>("/api/m/password/reset", { method: "POST", body: { token, password: pw.a } });
      setDone(true);
      if (r.member) {
        setMe(r.member);
        setTimeout(() => router.replace("/compte/"), 1500);
      }
    } catch (e2) {
      setErr(e2 instanceof Error ? e2.message : "Erreur");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="container-x grid min-h-[70vh] place-items-center py-14">
      <div className="card w-full max-w-md p-7 sm:p-9">
        <div className="flex items-center gap-3">
          <span className="grid size-11 place-items-center rounded-xl bg-brand-500/15 text-brand-300"><KeyRound className="size-5" /></span>
          <h1 className="font-[family-name:var(--font-display)] text-lg font-bold">Nouveau mot de passe</h1>
        </div>
        {!token ? (
          <Notice kind="error" className="mt-6">Lien incomplet : ouvrez le lien exact reçu par e-mail, ou refaites une demande depuis « Mot de passe oublié ».</Notice>
        ) : done ? (
          <div className="mt-6 grid gap-4">
            <Notice kind="ok">Mot de passe changé. Toutes vos anciennes connexions ont été fermées.</Notice>
            <Link href="/compte/" className="btn btn-primary">Ouvrir mon espace</Link>
          </div>
        ) : (
          <form onSubmit={submit} className="mt-6 grid gap-4">
            <PasswordField value={pw.a} onChange={(v) => setPw({ ...pw, a: v })} autoComplete="new-password" meter={strength(pw.a)} autoFocus />
            <label className="field"><span>Confirmez le mot de passe</span><input className="input" type="password" required minLength={12} autoComplete="new-password" value={pw.b} onChange={(e) => setPw({ ...pw, b: e.target.value })} /></label>
            {err && <Notice kind="error">{err}</Notice>}
            <button className="btn btn-primary" disabled={busy}>{busy ? <Spinner label="" /> : "Enregistrer"}</button>
          </form>
        )}
      </div>
    </div>
  );
}
