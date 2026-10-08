// The payment alert the team receives on Telegram, in the exact format the platform sends
// (hedgefund/members/alerts.py, OperatorAlerts.message), with the demonstration values.
import { Send } from "lucide-react";
import { AbsoluteFill, interpolate, useCurrentFrame, useVideoConfig } from "remotion";
import { Backdrop, Grain } from "../components/Backdrop";
import { Reveal } from "../components/Logo";
import { C, EASE, F } from "../theme";

const LINES = [
  "Paiement Wave à valider",
  "Moussa Fall (démo) · Starter (1 mois) · 17 000 FCFA",
  "Transaction Wave : DEMO-4F2A91C3",
  "Retrouvez ce transfert dans votre application Wave (même montant, même identifiant), puis validez-le : /admin/ (sur le serveur) → Paiements.",
];

const clamp01 = (v: number) => Math.min(1, Math.max(0, v));

export const AlertScene: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const t = frame / fps;
  const panel = EASE.out(clamp01((t - 0.2) / 0.8));
  const banner = interpolate(t, [0.9, 1.3, 2.6, 3.0], [0, 1, 1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const total = LINES.join("\n").length;
  const typed = Math.floor(total * clamp01((t - 1.4) / 3.0));
  let left = typed;
  return (
    <AbsoluteFill>
      <Backdrop glow={0.8} />
      <div style={{ position: "absolute", left: 160, top: 330, width: 640 }}>
        <Reveal start={0.2}>
          <div style={{ fontFamily: F.mono, fontSize: 18, letterSpacing: "0.32em", color: C.gold }}>PAYMENT ALERT</div>
        </Reveal>
        <div style={{ height: 20 }} />
        <Reveal start={0.35}>
          <div style={{ fontFamily: F.display, fontWeight: 800, fontSize: 64, lineHeight: 1.08, color: C.white }}>Une alerte, au moment du paiement</div>
        </Reveal>
        <div style={{ height: 26 }} />
        <div style={{ fontFamily: F.body, fontSize: 24, lineHeight: 1.5, color: C.grey, opacity: EASE.out(clamp01((t - 0.8) / 0.8)) }}>
          Format réel du message envoyé par la plateforme. Valeurs de démonstration.
        </div>
      </div>
      <div style={{ position: "absolute", left: 1000, top: 190, width: 700, height: 700, opacity: panel, transform: `perspective(1600px) rotateY(${(1 - panel) * -18}deg) translateX(${(1 - panel) * 60}px)`, borderRadius: 28, overflow: "hidden", background: "linear-gradient(180deg, #12141A, #0A0B0F)", border: `1px solid ${C.hair}`, boxShadow: "0 50px 140px -30px rgba(0,0,0,0.95), 0 0 100px -30px rgba(212,179,116,0.3)" }}>
        <div style={{ height: 84, display: "flex", alignItems: "center", gap: 16, padding: "0 26px", borderBottom: `1px solid ${C.hairSoft}` }}>
          <span style={{ width: 48, height: 48, borderRadius: 24, display: "grid", placeItems: "center", background: "rgba(212,179,116,0.12)", border: `1px solid ${C.hair}` }}>
            <Send size={22} color={C.gold} />
          </span>
          <div>
            <div style={{ fontFamily: F.body, fontWeight: 600, fontSize: 22, color: C.white }}>Bot de la plateforme</div>
            <div style={{ fontFamily: F.body, fontSize: 16, color: C.dim }}>Telegram · conversation de l'équipe</div>
          </div>
        </div>
        <div style={{ padding: 30 }}>
          <div style={{ maxWidth: 600, padding: "20px 24px", borderRadius: "20px 20px 20px 6px", background: "#1B1E26", border: `1px solid ${C.hairSoft}`, fontFamily: F.body, fontSize: 23, lineHeight: 1.5, color: C.white, opacity: clamp01((t - 1.3) / 0.3) }}>
            {LINES.map((l, i) => {
              const n = Math.max(0, Math.min(l.length, left));
              left -= l.length + 1;
              return (
                <div key={i} style={{ fontWeight: i === 0 ? 700 : 400, color: i === 0 ? C.goldLight : i === 3 ? C.grey : C.white, marginTop: i ? 8 : 0, minHeight: "1.5em" }}>
                  {l.slice(0, n)}
                  {n > 0 && n < l.length && <span style={{ color: C.gold }}>▍</span>}
                </div>
              );
            })}
          </div>
        </div>
      </div>
      <div style={{ position: "absolute", left: 1040, top: 92 + banner * 18, width: 620, opacity: banner, padding: "16px 22px", borderRadius: 18, background: "rgba(24,26,33,0.96)", border: `1px solid ${C.hair}`, display: "flex", gap: 14, alignItems: "center", boxShadow: "0 20px 50px -10px rgba(0,0,0,0.8)" }}>
        <Send size={20} color={C.gold} />
        <span style={{ fontFamily: F.body, fontSize: 20, color: C.white }}>Nouveau message · Paiement Wave à valider</span>
      </div>
      <Grain />
    </AbsoluteFill>
  );
};
