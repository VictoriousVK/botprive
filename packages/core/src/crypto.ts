import { createHash, createHmac, randomBytes, timingSafeEqual } from "node:crypto";

/** Comparaison en temps constant (évite les attaques par mesure du temps). */
export function safeEqual(a: string, b: string): boolean {
  const ba = Buffer.from(a);
  const bb = Buffer.from(b);
  if (ba.length !== bb.length) return false;
  return timingSafeEqual(ba, bb);
}

export function hmacSha256Hex(secret: string, message: string): string {
  return createHmac("sha256", secret).update(message).digest("hex");
}

export function hmacSha256Base64Url(secret: string, message: string): string {
  return createHmac("sha256", secret).update(message).digest("base64url");
}

export function sha256Hex(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

export function randomToken(bytes = 32): string {
  return randomBytes(bytes).toString("base64url");
}

/** Référence de paiement lisible et unique : VK-<horodatage base36>-<aléa>. */
export function newPaymentReference(now: Date = new Date()): string {
  return `VK-${now.getTime().toString(36).toUpperCase()}-${randomBytes(5).toString("hex").toUpperCase()}`;
}
