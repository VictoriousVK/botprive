/**
 * Faux Flutterwave + Wave pour développer sans compte marchand ni vrai paiement.
 *   pnpm mock:providers
 * Dans .env : FLW_API_BASE_URL=http://127.0.0.1:4010 et WAVE_API_BASE_URL=http://127.0.0.1:4010
 * La page de paiement factice envoie le webhook signé à APP_URL/api/webhooks/<prestataire>.
 */
import { MockProviders } from "@vk/core/testing";

const port = Number(process.env.MOCK_PROVIDERS_PORT ?? 4010);
const mock = new MockProviders({
  flwSecretKey: process.env.FLW_SECRET_KEY ?? "FLWSECK_TEST-mock",
  flwWebhookHash: process.env.FLW_WEBHOOK_HASH ?? "flw-webhook-hash-dev",
  waveApiKey: process.env.WAVE_API_KEY ?? "wave_sn_test_mock",
  waveWebhookSecret: process.env.WAVE_WEBHOOK_SECRET ?? "wave_sn_WHS_dev",
  webhookBaseUrl: process.env.APP_URL ?? "http://localhost:3000",
});
const url = await mock.start(port);
console.log(`Faux prestataires prêts sur ${url} (webhooks → ${process.env.APP_URL ?? "http://localhost:3000"})`);
process.on("SIGINT", async () => {
  await mock.stop();
  process.exit(0);
});
