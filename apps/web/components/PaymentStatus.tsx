"use client";

import { useEffect, useState } from "react";

type State = "pending" | "succeeded" | "failed" | "refunded" | "unknown";

/** Interroge le serveur jusqu'à la confirmation (webhook + vérification). N'accorde rien lui-même. */
export function PaymentStatus({ reference, initial, inviteUrl }: { reference: string; initial: State; inviteUrl: string }) {
  const [state, setState] = useState<State>(initial);
  const [tries, setTries] = useState(0);

  useEffect(() => {
    if (state !== "pending" || tries > 40) return;
    const timer = setTimeout(async () => {
      try {
        const res = await fetch(`/api/payments/${encodeURIComponent(reference)}`, { cache: "no-store" });
        if (res.ok) {
          const data = (await res.json()) as { status: State };
          setState(data.status);
        }
      } finally {
        setTries((t) => t + 1);
      }
    }, 3000);
    return () => clearTimeout(timer);
  }, [state, tries, reference]);

  if (state === "succeeded") {
    return (
      <div className="alert success" role="status">
        <p style={{ marginTop: 0 }}>
          <strong>Paiement confirmé, bienvenue dans le club !</strong> Ton rôle Discord est attribué automatiquement. Tu reçois aussi un
          message privé et un email.
        </p>
        <div className="actions">
          <a className="btn" href={inviteUrl} rel="noopener noreferrer">
            Ouvrir le Discord
          </a>
          <a className="btn ghost" href="/espace">
            Mon espace
          </a>
        </div>
      </div>
    );
  }
  if (state === "failed") {
    return (
      <div className="alert error" role="alert">
        <p style={{ marginTop: 0 }}>Le paiement n'a pas abouti. Aucun montant n'a été validé.</p>
        <a className="btn" href="/inscription">
          Réessayer
        </a>
      </div>
    );
  }
  return (
    <div className="alert" role="status" aria-live="polite">
      <p style={{ margin: 0 }}>
        {tries > 40
          ? "La confirmation prend plus de temps que prévu. Ton accès sera activé automatiquement dès que le prestataire confirme le paiement : tu recevras un message Discord et un email."
          : "Vérification du paiement auprès du prestataire… (quelques secondes)"}
      </p>
    </div>
  );
}
