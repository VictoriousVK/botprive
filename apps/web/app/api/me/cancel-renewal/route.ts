import { cancelRenewal, DomainError } from "@vk/core";
import { isSameOrigin, redirectTo } from "@/lib/security";
import { getCurrentMember, getDeps } from "@/lib/server";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  if (!isSameOrigin(request)) return redirectTo("/espace?erreur=csrf");
  const member = await getCurrentMember();
  if (!member) return redirectTo("/espace");
  const deps = getDeps();
  try {
    await cancelRenewal(deps, member.id, { type: "member", id: member.discordUserId });
    return redirectTo("/espace?ok=annule");
  } catch (error) {
    if (error instanceof DomainError) return redirectTo(`/espace?erreur=${error.code}`);
    deps.logger.error(`Annulation : ${error instanceof Error ? error.message : String(error)}`);
    return redirectTo("/espace?erreur=provider_error");
  }
}
