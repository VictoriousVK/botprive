import { z } from "zod";
import { DomainError, PLAN_IDS, startCheckout } from "@vk/core";
import { rateLimit, tooManyRequests } from "@/lib/rate-limit";
import { clientIp, isSameOrigin, redirectTo } from "@/lib/security";
import { getCurrentMember, getDeps } from "@/lib/server";

export const dynamic = "force-dynamic";

const schema = z.object({
  plan: z.enum(PLAN_IDS as [string, ...string[]]),
  method: z.enum(["card", "mobile_money"]),
  autoRenew: z.literal("on").optional(),
  consent: z.literal("on").optional(),
  email: z.string().trim().email().max(200),
  phone: z
    .string()
    .trim()
    .max(30)
    .regex(/^[+0-9 ()-]*$/)
    .optional(),
});

/** Crée la session de paiement puis redirige vers le prestataire. */
export async function POST(request: Request) {
  if (!isSameOrigin(request)) return redirectTo("/inscription?erreur=csrf");
  if (!rateLimit(`checkout:${clientIp(request)}`, 10, 60_000)) return tooManyRequests();
  const member = await getCurrentMember();
  if (!member) return redirectTo("/inscription");

  const form = Object.fromEntries(await request.formData());
  const parsed = schema.safeParse(form);
  const planParam = typeof form.plan === "string" && PLAN_IDS.includes(form.plan as never) ? form.plan : "quarterly";
  if (!parsed.success) return redirectTo(`/inscription?plan=${planParam}&erreur=invalid_form`);
  const input = parsed.data;
  const autoRenew = input.method === "card" && input.autoRenew === "on";

  const deps = getDeps();
  try {
    const result = await startCheckout(deps, {
      memberId: member.id,
      planId: input.plan as (typeof PLAN_IDS)[number],
      method: input.method,
      autoRenew,
      autoRenewConsent: input.consent === "on",
      email: input.email,
      phone: input.phone || null,
    });
    return new Response(null, { status: 303, headers: { location: result.redirectUrl } });
  } catch (error) {
    if (error instanceof DomainError) return redirectTo(`/inscription?plan=${input.plan}&erreur=${error.code}`);
    deps.logger.error(`Checkout : ${error instanceof Error ? error.message : String(error)}`);
    return redirectTo(`/inscription?plan=${input.plan}&erreur=provider_error`);
  }
}
