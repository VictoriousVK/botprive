import { z } from "zod";
import { DomainError, getMember, signingSecret, startCheckout, verifyRenewalToken } from "@vk/core";
import { rateLimit, tooManyRequests } from "@/lib/rate-limit";
import { clientIp, isSameOrigin, redirectTo } from "@/lib/security";
import { getDeps } from "@/lib/server";

export const dynamic = "force-dynamic";

const schema = z.object({ token: z.string().min(10).max(500), method: z.enum(["card", "mobile_money"]) });

/** Paiement en 1 clic depuis un lien de rappel signé (sans connexion). */
export async function POST(request: Request) {
  if (!isSameOrigin(request)) return redirectTo("/espace?erreur=csrf");
  if (!rateLimit(`renew:${clientIp(request)}`, 10, 60_000)) return tooManyRequests();
  const deps = getDeps();
  const parsed = schema.safeParse(Object.fromEntries(await request.formData()));
  if (!parsed.success) return redirectTo("/espace?erreur=link_invalid");
  const claims = verifyRenewalToken(signingSecret(deps.env), parsed.data.token, deps.now());
  const member = claims ? await getMember(deps.db, claims.memberId) : null;
  if (!claims || !member) return redirectTo("/espace?erreur=link_invalid");
  try {
    const result = await startCheckout(deps, {
      memberId: member.id,
      planId: claims.planId,
      method: parsed.data.method,
      autoRenew: false,
      autoRenewConsent: false,
    });
    return new Response(null, { status: 303, headers: { location: result.redirectUrl } });
  } catch (error) {
    const code = error instanceof DomainError ? error.code : "provider_error";
    if (!(error instanceof DomainError)) deps.logger.error(`Renouvellement 1 clic : ${String(error)}`);
    return redirectTo(`/r/${encodeURIComponent(parsed.data.token)}?erreur=${code}`);
  }
}
