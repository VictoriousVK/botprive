import Link from "next/link";
import { formatXof, PLANS } from "@vk/core";

const PERKS = ["3 lives par semaine (MAR · MER · VEN)", "Telegram privé, replays et débriefs", "Stratégies Gold exclusives", "1 invité spécial chaque semaine"];

export function PlanCards() {
  return (
    <div className="plans">
      {Object.values(PLANS).map((plan) => {
        const highlight = Boolean(plan.badge);
        return (
          <article key={plan.id} className={`card plan${highlight ? " highlight" : ""}`} aria-labelledby={`plan-${plan.id}`}>
            {plan.badge ? <span className="ribbon">{plan.badge}</span> : null}
            <p className="label">{plan.months === 1 ? "1 mois" : `${plan.months} mois`}</p>
            <h3 id={`plan-${plan.id}`} className="display">
              {plan.label}
            </h3>
            <div className="price">
              <span className="display">{plan.priceUsd}</span>
              <span className="display" style={{ fontSize: "2rem" }}>$</span>
            </div>
            <p className="price-xof">{formatXof(plan.priceXof)} · prix payé</p>
            <p className="muted" style={{ margin: 0 }}>{plan.tagline}</p>
            <ul>
              {PERKS.map((perk) => (
                <li key={perk}>{perk}</li>
              ))}
            </ul>
            <Link className={`btn block${highlight ? "" : " ghost"}`} href={`/inscription?plan=${plan.id}`}>
              Choisir {plan.label.toLowerCase()}
            </Link>
          </article>
        );
      })}
    </div>
  );
}
