/*
 * Limitation de débit en mémoire (fenêtre glissante), suffisante pour une instance unique.
 * Avec plusieurs instances du site, remplacer par un stockage partagé.
 */

const buckets = new Map<string, number[]>();
let lastSweep = Date.now();

export function rateLimit(key: string, limit: number, windowMs: number): boolean {
  const now = Date.now();
  if (now - lastSweep > 60_000) {
    for (const [k, hits] of buckets) if (hits.every((t) => now - t > windowMs)) buckets.delete(k);
    lastSweep = now;
  }
  const hits = (buckets.get(key) ?? []).filter((t) => now - t < windowMs);
  if (hits.length >= limit) {
    buckets.set(key, hits);
    return false;
  }
  hits.push(now);
  buckets.set(key, hits);
  return true;
}

export function tooManyRequests(): Response {
  return new Response("Trop de requêtes, réessaie dans une minute.", { status: 429, headers: { "retry-after": "60" } });
}
