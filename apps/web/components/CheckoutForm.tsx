"use client";

import { useState } from "react";

export interface PlanOption {
  id: string;
  label: string;
  months: number;
  priceUsd: number;
  priceXofLabel: string;
  badge?: string;
}

interface Props {
  plans: PlanOption[];
  initialPlan: string;
  email: string;
  phone: string;
  card: boolean;
  mobileMoney: boolean;
  mobileMoneyLabel: string;
  /** Formules pour lesquelles le renouvellement automatique par carte est configuré. */
  autoRenewPlans: string[];
}

/** Formulaire de paiement. Fonctionne sans JavaScript (envoi classique) ; JS sert seulement à l'affichage. */
export function CheckoutForm(props: Props) {
  const [planId, setPlanId] = useState(props.initialPlan);
  const [method, setMethod] = useState(props.mobileMoney ? "mobile_money" : "card");
  const [autoRenew, setAutoRenew] = useState(false);
  const plan = props.plans.find((p) => p.id === planId) ?? props.plans[0]!;
  const autoAvailable = method === "card" && props.autoRenewPlans.includes(planId);

  return (
    <form className="form" method="post" action="/api/checkout">
      <fieldset>
        <legend>1 · Formule</legend>
        {props.plans.map((p) => (
          <label key={p.id} className="choice">
            <input type="radio" name="plan" value={p.id} checked={planId === p.id} onChange={() => setPlanId(p.id)} />
            <span>
              <strong>
                {p.label} · {p.priceXofLabel}
                {p.badge ? ` · ${p.badge}` : ""}
              </strong>
              <small>
                {p.months === 1 ? "1 mois" : `${p.months} mois`} · {p.priceUsd} $ indicatif
              </small>
            </span>
          </label>
        ))}
      </fieldset>

      <fieldset>
        <legend>2 · Moyen de paiement</legend>
        {props.mobileMoney ? (
          <label className="choice">
            <input type="radio" name="method" value="mobile_money" checked={method === "mobile_money"} onChange={() => setMethod("mobile_money")} />
            <span>
              <strong>Mobile Money · {props.mobileMoneyLabel}</strong>
              <small>Tu valides sur ton téléphone. Renouvellement par rappel (J-3, J-1, J0) avec lien en 1 clic.</small>
            </span>
          </label>
        ) : null}
        {props.card ? (
          <label className="choice">
            <input type="radio" name="method" value="card" checked={method === "card"} onChange={() => setMethod("card")} />
            <span>
              <strong>Carte bancaire</strong>
              <small>Visa, Mastercard. Renouvellement automatique possible, avec ton accord.</small>
            </span>
          </label>
        ) : null}
        {method === "card" && autoAvailable ? (
          <label className="choice">
            <input type="checkbox" name="autoRenew" checked={autoRenew} onChange={(e) => setAutoRenew(e.target.checked)} />
            <span>
              <strong>Renouvellement automatique</strong>
              <small>Ta carte sera débitée à chaque échéance. Annulable à tout moment depuis ton espace.</small>
            </span>
          </label>
        ) : null}
        {method === "card" && autoRenew && autoAvailable ? (
          <label className="choice consent">
            <input type="checkbox" name="consent" required />
            <span>
              <strong>J'accepte le prélèvement automatique</strong>
              <small>
                J'autorise le prélèvement de {plan.priceXofLabel} tous les {plan.months === 1 ? "mois" : `${plan.months} mois`} sur ma carte,
                jusqu'à annulation de ma part depuis mon espace membre, selon les conditions générales de vente.
              </small>
            </span>
          </label>
        ) : null}
      </fieldset>

      <fieldset>
        <legend>3 · Coordonnées</legend>
        <div className="field">
          <label htmlFor="email">Email (reçus et rappels)</label>
          <input id="email" name="email" type="email" required autoComplete="email" defaultValue={props.email} />
        </div>
        <div className="field">
          <label htmlFor="phone">Téléphone (facultatif)</label>
          <input id="phone" name="phone" type="tel" autoComplete="tel" inputMode="tel" placeholder="+221 …" defaultValue={props.phone} />
        </div>
      </fieldset>

      <button className="btn block" type="submit">
        Payer {plan.priceXofLabel}
      </button>
      <p className="muted" style={{ margin: 0, fontSize: "0.85rem" }}>
        Tu es redirigé vers la page sécurisée du prestataire de paiement. Ton accès est activé dès que le paiement est confirmé par le
        prestataire (pas avant). En payant, tu acceptes les <a href="/cgv">conditions générales de vente</a>.
      </p>
    </form>
  );
}
