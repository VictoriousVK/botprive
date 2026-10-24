import { getPaymentForMember, getSubscriptionForMember } from "@vk/core";
import { getCurrentMember, getDeps } from "@/lib/server";

export const dynamic = "force-dynamic";

/** Statut d'un paiement du membre connecté (jamais celui d'un autre membre). */
export async function GET(_request: Request, { params }: { params: Promise<{ reference: string }> }) {
  const member = await getCurrentMember();
  if (!member) return Response.json({ error: "unauthenticated" }, { status: 401 });
  const { reference } = await params;
  const deps = getDeps();
  const payment = await getPaymentForMember(deps, member.id, reference);
  if (!payment) return Response.json({ error: "not_found" }, { status: 404 });
  const sub = await getSubscriptionForMember(deps.db, member.id);
  return Response.json(
    { status: payment.status, subscriptionStatus: sub?.status ?? null, periodEnd: sub?.currentPeriodEnd ?? null },
    { headers: { "cache-control": "no-store" } },
  );
}
