"use client";

import { motion } from "framer-motion";
import { CircleCheck, TriangleAlert } from "lucide-react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { Notice, Spinner } from "@/components/ui";
import { api, type Me } from "@/lib/api";
import { useSession } from "@/lib/session";

// Landing page of the confirmation link sent by e-mail: /compte/verifier/?jeton=...
export function VerifyView() {
  const token = useSearchParams().get("jeton") ?? "";
  const { setMe } = useSession();
  const router = useRouter();
  const [state, setState] = useState<"busy" | "ok" | "error">(token ? "busy" : "error");
  const [msg, setMsg] = useState(token ? "" : "Lien incomplet : ouvrez le lien exact reçu par e-mail.");
  const done = useRef(false); // the link works once: never send it twice (React strict mode)

  useEffect(() => {
    if (!token || done.current) return;
    done.current = true;
    window.history.replaceState(null, "", "/compte/verifier/"); // the token leaves the address bar
    api<Me>("/api/m/verify", { method: "POST", body: { token } })
      .then((m) => {
        setMe(m);
        setState("ok");
        setTimeout(() => router.replace("/compte/"), 1800);
      })
      .catch((e) => {
        setMsg(e instanceof Error ? e.message : "Erreur");
        setState("error");
      });
  }, [token, setMe, router]);

  return (
    <div className="container-x grid min-h-[70vh] place-items-center py-14">
      <motion.div initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} className="card w-full max-w-md p-8 text-center">
        {state === "busy" && <Spinner label="Confirmation en cours…" />}
        {state === "ok" && (
          <>
            <CircleCheck className="mx-auto size-12 text-up-400" />
            <h1 className="mt-4 font-[family-name:var(--font-display)] text-xl font-bold">Adresse confirmée</h1>
            <p className="mt-2 text-sm text-muted">Bienvenue ! Votre compte est actif. Redirection vers votre espace…</p>
            <Link href="/compte/" className="btn btn-primary mt-6">Ouvrir mon espace</Link>
          </>
        )}
        {state === "error" && (
          <>
            <TriangleAlert className="mx-auto size-12 text-gold-400" />
            <h1 className="mt-4 font-[family-name:var(--font-display)] text-xl font-bold">Lien non valide</h1>
            <Notice kind="error" className="mt-4 text-left">{msg}</Notice>
            <p className="mt-4 text-sm text-muted">Connectez-vous avec votre e-mail et votre mot de passe : vous pourrez demander un nouveau lien.</p>
            <Link href="/compte/?vue=connexion" className="btn btn-primary mt-6">Aller à la connexion</Link>
          </>
        )}
      </motion.div>
    </div>
  );
}
