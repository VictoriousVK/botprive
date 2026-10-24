import { handleWebhook } from "@vk/core";
import { rateLimit, tooManyRequests } from "@/lib/rate-limit";
import { clientIp } from "@/lib/security";
import { getDeps } from "@/lib/server";

export const dynamic = "force-dynamic";

/**
 * Webhooks des prestataires. Le corps brut est lu tel quel (indispensable pour la signature).
 * URL à déclarer : https://<domaine>/api/webhooks/flutterwave et /api/webhooks/wave
 */
export async function POST(request: Request, { params }: { params: Promise<{ provider: string }> }) {
  if (!rateLimit(`webhook:${clientIp(request)}`, 300, 60_000)) return tooManyRequests();
  const { provider } = await params;
  const rawBody = await request.text();
  if (rawBody.length > 256_000) return Response.json({ error: "payload_too_large" }, { status: 413 });
  const headers: Record<string, string> = {};
  request.headers.forEach((value, key) => {
    headers[key.toLowerCase()] = value;
  });
  const result = await handleWebhook(getDeps(), provider, { headers, rawBody });
  return Response.json(result.body, { status: result.httpStatus });
}
