/**
 * Envoie un webhook signé (ou volontairement falsifié) à l'application locale.
 *
 *   pnpm webhook:send --provider wave --checkout cos-xxx --ref VK-XXX
 *   pnpm webhook:send --provider flutterwave --tx 9000001 --ref VK-XXX
 *   options : --status succeeded|failed  --forge (mauvaise signature)  --replay (horodatage de 10 min)
 *             --url http://localhost:3000
 *
 * L'application revérifie toujours le paiement auprès de l'API du prestataire (ici le faux serveur) :
 * un webhook seul n'accorde jamais d'accès.
 */
import { parseArgs } from "node:util";
import { signWavePayload } from "@vk/core";

const { values } = parseArgs({
  options: {
    provider: { type: "string", default: "wave" },
    ref: { type: "string" },
    checkout: { type: "string" },
    tx: { type: "string" },
    status: { type: "string", default: "succeeded" },
    forge: { type: "boolean", default: false },
    replay: { type: "boolean", default: false },
    url: { type: "string", default: process.env.APP_URL ?? "http://localhost:3000" },
  },
});

let headers: Record<string, string>;
let body: string;
const ok = values.status === "succeeded";

if (values.provider === "wave") {
  body = JSON.stringify({
    id: `EV_manual_${Date.now()}`,
    type: ok ? "checkout.session.completed" : "checkout.session.payment_failed",
    data: { id: values.checkout, client_reference: values.ref, payment_status: ok ? "succeeded" : "cancelled", checkout_status: ok ? "complete" : "expired" },
  });
  const secret = values.forge ? "secret-falsifie" : process.env.WAVE_WEBHOOK_SECRET ?? "wave_sn_WHS_dev";
  const when = values.replay ? new Date(Date.now() - 10 * 60_000) : new Date();
  headers = { "wave-signature": signWavePayload(body, secret, when) };
} else {
  body = JSON.stringify({ event: "charge.completed", data: { id: Number(values.tx), tx_ref: values.ref, status: ok ? "successful" : "failed" } });
  headers = { "verif-hash": values.forge ? "hash-falsifie" : process.env.FLW_WEBHOOK_HASH ?? "flw-webhook-hash-dev" };
}

const res = await fetch(`${values.url.replace(/\/$/, "")}/api/webhooks/${values.provider}`, {
  method: "POST",
  headers: { "content-type": "application/json", ...headers },
  body,
});
console.log(`HTTP ${res.status} ${await res.text()}`);
