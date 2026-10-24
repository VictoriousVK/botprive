import type { AppEnv } from "../config/env";
import { required } from "../config/env";
import { DomainError } from "../errors";
import type { FetchLike } from "../http";
import type { Logger } from "../logger";
import { FlutterwaveProvider } from "./providers/flutterwave";
import { PAYDUNYA_LIVE_URL, PAYDUNYA_SANDBOX_URL, PayDunyaProvider } from "./providers/paydunya";
import { WaveProvider } from "./providers/wave";
import type { PaymentMethod, PaymentProvider, ProviderId } from "./types";

export interface ProviderRegistry {
  get(id: string): PaymentProvider;
  has(id: string): boolean;
  /** Prestataire configuré pour un moyen de paiement, ou null si ce moyen est désactivé. */
  forMethod(method: PaymentMethod): PaymentProvider | null;
  all(): PaymentProvider[];
  /** Prestataires écartés au démarrage (ex : clé réelle en mode test), avec la raison. */
  disabled: { id: ProviderId; reason: string }[];
}

export function createRegistry(
  providers: PaymentProvider[],
  routing: Partial<Record<PaymentMethod, ProviderId>>,
  disabled: { id: ProviderId; reason: string }[] = [],
): ProviderRegistry {
  const byId = new Map(providers.map((p) => [p.id, p] as const));
  return {
    get(id) {
      const provider = byId.get(id as ProviderId);
      if (!provider) throw new DomainError("provider_disabled", `Prestataire non configuré : ${id}`);
      return provider;
    },
    has: (id) => byId.has(id as ProviderId),
    forMethod(method) {
      const id = routing[method];
      return id ? byId.get(id) ?? null : null;
    },
    all: () => [...byId.values()],
    disabled,
  };
}

/**
 * Construit les prestataires activés à partir du .env.
 * En PAYMENT_MODE=test (défaut), un prestataire configuré avec des clés ou une adresse réelles est
 * écarté : aucun encaissement réel n'est possible tant que le mode live n'est pas choisi.
 */
export function createProviderRegistry(env: AppEnv, fetchImpl?: FetchLike, logger?: Logger): ProviderRegistry {
  const wanted = new Set<ProviderId>();
  if (env.PAYMENT_PROVIDER_CARD !== "none") wanted.add(env.PAYMENT_PROVIDER_CARD);
  if (env.PAYMENT_PROVIDER_MOBILE_MONEY !== "none") wanted.add(env.PAYMENT_PROVIDER_MOBILE_MONEY);

  const candidates: PaymentProvider[] = [];
  const disabled: { id: ProviderId; reason: string }[] = [];
  if (wanted.has("flutterwave") && env.FLW_SECRET_KEY) {
    candidates.push(
      new FlutterwaveProvider({
        secretKey: env.FLW_SECRET_KEY,
        webhookHash: required(env, "FLW_WEBHOOK_HASH"),
        baseUrl: env.FLW_API_BASE_URL,
        mobileMoneyOption: env.FLW_MOBILE_MONEY_OPTION,
        fetch: fetchImpl,
      }),
    );
  }
  if (wanted.has("wave") && env.WAVE_API_KEY) {
    candidates.push(
      new WaveProvider({
        apiKey: env.WAVE_API_KEY,
        webhookSecret: required(env, "WAVE_WEBHOOK_SECRET"),
        baseUrl: env.WAVE_API_BASE_URL,
        fetch: fetchImpl,
      }),
    );
  }
  if (wanted.has("paydunya") && env.PAYDUNYA_PRIVATE_KEY) {
    candidates.push(
      new PayDunyaProvider({
        masterKey: required(env, "PAYDUNYA_MASTER_KEY"),
        privateKey: env.PAYDUNYA_PRIVATE_KEY,
        token: required(env, "PAYDUNYA_TOKEN"),
        baseUrl: env.PAYDUNYA_API_BASE_URL ?? (env.PAYMENT_MODE === "live" ? PAYDUNYA_LIVE_URL : PAYDUNYA_SANDBOX_URL),
        callbackUrl: `${env.APP_URL.replace(/\/$/, "")}/api/webhooks/paydunya`,
        fetch: fetchImpl,
      }),
    );
  }

  const providers: PaymentProvider[] = [];
  for (const p of candidates) {
    if (env.PAYMENT_MODE === "test" && !p.testMode) {
      const reason = "clé ou adresse réelle alors que PAYMENT_MODE=test : désactivé (aucun encaissement réel en mode test)";
      disabled.push({ id: p.id, reason });
      logger?.warn(`Prestataire ${p.id} ${reason}`);
      continue;
    }
    providers.push(p);
  }

  const routing: Partial<Record<PaymentMethod, ProviderId>> = {};
  if (env.PAYMENT_PROVIDER_CARD !== "none") routing.card = env.PAYMENT_PROVIDER_CARD;
  if (env.PAYMENT_PROVIDER_MOBILE_MONEY !== "none") routing.mobile_money = env.PAYMENT_PROVIDER_MOBILE_MONEY;
  return createRegistry(providers, routing, disabled);
}
