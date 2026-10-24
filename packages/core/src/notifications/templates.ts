import { CLUB } from "../config/club";
import { daysBetween, formatDate, formatXof } from "../dates";
import type { NotificationTemplate } from "../outbox";

export interface TemplateContext {
  memberName: string;
  planLabel: string;
  /** null = tarif pas encore défini. */
  priceXof: number | null;
  /** Résumé des horaires des lives, ou null s'ils ne sont pas encore fixés. */
  liveSchedule: string | null;
  scheduleDays: string;
  /** Prélèvement carte actif : on n'envoie JAMAIS de lien de paiement manuel (double paiement). */
  autoRenewActive: boolean;
  periodEnd: Date | null;
  graceEndsAt: Date | null;
  renewalUrl: string;
  accountUrl: string;
  inviteUrl: string;
  telegramUrl?: string;
  now: Date;
}

export interface RenderedNotification {
  /** Message privé Discord (markdown Discord). */
  dm: string;
  email: { subject: string; text: string; html: string };
}

const SIGNATURE = `— Victor · ${CLUB.name}\n${CLUB.signatures[0]}`;

function remaining(ctx: TemplateContext): string {
  if (!ctx.periodEnd) return "";
  const days = daysBetween(ctx.now, ctx.periodEnd);
  if (days <= 0) return "aujourd'hui";
  if (days === 1) return "demain";
  return `dans ${days} jours`;
}

function body(template: NotificationTemplate, ctx: TemplateContext): { subject: string; lines: string[] } | null {
  const end = ctx.periodEnd ? formatDate(ctx.periodEnd) : "—";
  const grace = ctx.graceEndsAt ? formatDate(ctx.graceEndsAt) : end;
  const price = ctx.priceXof === null ? ctx.planLabel : `${ctx.planLabel} · ${formatXof(ctx.priceXof)}`;
  switch (template) {
    case "welcome":
      return {
        subject: "Bienvenue dans le V_ICT_ORIOUS Live Club",
        lines: [
          `Bienvenue ${ctx.memberName} ! 🎉`,
          `Ton accès au **${CLUB.name}** est actif jusqu'au **${end}**.`,
          `Lives chaque ${ctx.scheduleDays} : Live · Q&A · Débrief.${ctx.liveSchedule ? ` (${ctx.liveSchedule})` : " Horaires annoncés sur le Discord."}`,
          ...(ctx.telegramUrl ? [`Rejoins notre groupe Telegram (replays des sessions, cours, débriefs) : ${ctx.telegramUrl}`] : []),
          `Serveur Discord : ${ctx.inviteUrl}`,
          `Ton espace membre : ${ctx.accountUrl}`,
          `« ${CLUB.quote} »`,
        ],
      };
    case "renewed":
      return {
        subject: "Paiement reçu : accès prolongé",
        lines: [`Merci ${ctx.memberName}, paiement bien reçu ✅`, `Ton accès est prolongé jusqu'au **${end}** (${price}).`, `Historique et reçus : ${ctx.accountUrl}`],
      };
    case "reminder":
      if (ctx.autoRenewActive) {
        return {
          subject: `Renouvellement automatique le ${end}`,
          lines: [
            `Bonjour ${ctx.memberName},`,
            `Ton abonnement sera renouvelé **automatiquement par carte** le **${end}** (${price}). Tu n'as rien à faire.`,
            `Pour vérifier ou annuler le renouvellement : ${ctx.accountUrl}`,
          ],
        };
      }
      return {
        subject: `Ton accès se termine le ${end}`,
        lines: [
          `Bonjour ${ctx.memberName},`,
          `Ton accès au ${CLUB.name} se termine **${remaining(ctx)}** (${end}).`,
          `Renouvelle en 1 clic (${price}) : ${ctx.renewalUrl}`,
          `Ta nouvelle période démarre à la fin de l'actuelle : tu ne perds aucun jour.`,
        ],
      };
    case "grace_started":
      if (ctx.autoRenewActive) {
        return {
          subject: "Le prélèvement de ton abonnement n'a pas abouti",
          lines: [
            `Bonjour ${ctx.memberName},`,
            `Le prélèvement automatique de ton abonnement n'a pas encore abouti. Tu gardes l'accès jusqu'au **${grace}** (période de grâce).`,
            `Vérifie ta carte, ou annule le prélèvement dans ton espace pour payer autrement : ${ctx.accountUrl}`,
          ],
        };
      }
      return {
        subject: `Période de grâce : accès jusqu'au ${grace}`,
        lines: [
          `Bonjour ${ctx.memberName},`,
          `Ta période payée s'est terminée le ${end}. Tu gardes l'accès jusqu'au **${grace}** (période de grâce).`,
          `Renouvelle ici pour ne rien manquer (${price}) : ${ctx.renewalUrl}`,
        ],
      };
    case "expired":
      return {
        subject: "Ton accès au Live Club est terminé",
        lines: [
          `Bonjour ${ctx.memberName},`,
          `Ton accès aux salons privés du ${CLUB.name} est terminé. Tu restes sur le serveur public.`,
          ctx.autoRenewActive
            ? `Pour régulariser ton abonnement : ${ctx.accountUrl}`
            : `Pour revenir, c'est ici : ${ctx.renewalUrl} (accès rétabli automatiquement dès le paiement confirmé).`,
        ],
      };
    case "renewal_canceled":
      return {
        subject: "Renouvellement annulé",
        lines: [
          `Bonjour ${ctx.memberName},`,
          `Le renouvellement de ton abonnement est annulé. Tu gardes l'accès jusqu'au **${end}**.`,
          `Tu pourras revenir quand tu veux : ${ctx.renewalUrl}`,
        ],
      };
    case "admin_granted":
      return {
        subject: "Ton accès a été prolongé",
        lines: [`Bonjour ${ctx.memberName},`, `Ton accès au ${CLUB.name} est actif jusqu'au **${end}**.`, `Ton espace membre : ${ctx.accountUrl}`],
      };
  }
}

function escapeHtml(value: string): string {
  return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

function lineToHtml(line: string): string {
  return escapeHtml(line)
    .replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
    .replace(/(https?:\/\/[^\s<)]+)/g, '<a href="$1" style="color:#b98bff">$1</a>');
}

export function renderNotification(template: NotificationTemplate, ctx: TemplateContext): RenderedNotification | null {
  const content = body(template, ctx);
  if (!content) return null;
  const text = [...content.lines, "", SIGNATURE].join("\n");
  const html = `<!doctype html><html lang="fr"><body style="margin:0;background:#0b0a10;color:#ece9f5;font-family:Arial,Helvetica,sans-serif">
<div style="max-width:560px;margin:0 auto;padding:32px 24px">
<p style="font-family:monospace;letter-spacing:3px;font-size:12px;color:#9d5cf5;margin:0 0 24px">V_ICT_ORIOUS · LIVE TRADING CLUB</p>
${content.lines.map((l) => `<p style="font-size:16px;line-height:1.5;margin:0 0 14px">${lineToHtml(l)}</p>`).join("\n")}
<p style="font-size:13px;color:#9a96a8;margin-top:28px;white-space:pre-line">${escapeHtml(SIGNATURE)}</p>
</div></body></html>`;
  return {
    dm: [...content.lines].join("\n"),
    email: { subject: content.subject, text: text.replace(/\*\*/g, ""), html },
  };
}
