import Link from "next/link";
import { formatXof, type CatalogPlan } from "@vk/core";

export function PlanCards({ plans, days }: { plans: CatalogPlan[]; days: string[] }) {
  const visible = plans.filter((p) => p.enabled);
  const PERKS = [`${days.length} lives par semaine (${days.join(" · ")})`, "Telegram : replays, cours et débriefs", "Stratégies Gold exclusives", "1 invité spécial chaque semaine"];
  return (
    <div className="plans">
      {visible.map((plan) => {
        const highlight = Boolean(plan.badge);
        return (
          <article key={plan.id} className={`card plan${highlight ? " highlight" : ""}`} aria-labelledby={`plan-${plan.id}`}>
            {plan.badge ? <span className="ribbon">{plan.badge}</span> : null}
            <p className="label">{plan.months === 1 ? "1 mois" : `${plan.months} mois`}</p>
            <h3 id={`plan-${plan.id}`} className="display">
              {plan.label}
            </h3>
            {plan.priceUsd !== null ? (
              <div className="price">
                <span className="display">{plan.priceUsd}</span>
                <span className="display" style={{ fontSize: "2rem" }}>$</span>
              </div>
            ) : null}
            <p className="price-xof">{plan.priceXof !== null ? `${formatXof(plan.priceXof)} · prix payé` : "Tarif en FCFA bientôt disponible"}</p>
            <p className="muted" style={{ margin: 0 }}>{plan.tagline}</p>
            <ul>
              {PERKS.map((perk) => (
                <li key={perk}>{perk}</li>
              ))}
            </ul>
            {plan.purchasable ? (
              <Link className={`btn block${highlight ? "" : " ghost"}`} href={`/inscription?plan=${plan.id}`}>
                Choisir {plan.label.toLowerCase()}
              </Link>
            ) : (
              <span className="btn block ghost" aria-disabled="true">
                Bientôt disponible
              </span>
            )}
          </article>
        );
      })}
    </div>
  );
}
