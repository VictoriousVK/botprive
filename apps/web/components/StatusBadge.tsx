import { STATUS_LABELS, type SubscriptionStatus } from "@vk/core";

const TONE: Record<SubscriptionStatus, "ok" | "warn" | "off"> = {
  active: "ok",
  renewal_due: "warn",
  grace_period: "warn",
  canceled: "warn",
  pending_payment: "off",
  expired: "off",
  refunded: "off",
  suspended: "off",
};

export function StatusBadge({ status }: { status: SubscriptionStatus | null }) {
  if (!status) return <span className="status off">Aucun abonnement</span>;
  return <span className={`status ${TONE[status]}`}>{STATUS_LABELS[status]}</span>;
}
