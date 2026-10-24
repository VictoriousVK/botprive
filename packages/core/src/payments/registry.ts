import type { AppEnv } from "../config/env";
import { required } from "../config/env";
import { DomainError } from "../errors";
import type { FetchLike } from "../http";
import { FlutterwaveProvider } from "./providers/flutterwave";
import { WaveProvider } from "./providers/wave";
import type { PaymentMethod, PaymentProvider, ProviderId } from "./types";

export interface ProviderRegistry {
  get(id: string): PaymentProvider;
  has(id: string): boolean;
  /** Prestataire configuré pour un moyen de paiement, ou null si ce moyen est désactivé. */
  forMethod(method: PaymentMethod): PaymentProvider | null;
  all(): PaymentProvider[];
}

export function createRegistry(providers: PaymentProvider[], routing: Partial<Record<PaymentMethod, ProviderId>>): ProviderRegistry {
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
  };
}

/** Construit les prestataires activés à partir du .env. */
export function createProviderRegistry(env: AppEnv, fetchImpl?: FetchLike): ProviderRegistry {
  const wanted = new Set<ProviderId>();
  if (env.PAYMENT_PROVIDER_CARD !== "none") wanted.add(env.PAYMENT_PROVIDER_CARD);
  if (env.PAYMENT_PROVIDER_MOBILE_MONEY !== "none") wanted.add(env.PAYMENT_PROVIDER_MOBILE_MONEY);

  const providers: PaymentProvider[] = [];
  if (wanted.has("flutterwave") && env.FLW_SECRET_KEY) {
    providers.push(
      new FlutterwaveProvider({
        secretKey: env.FLW_SECRET_KEY,
        webhookHash: required(env, "FLW_WEBHOOK_HASH"),
        baseUrl: env.FLW_API_BASE_URL,
        mobileMoneyOption: env.FLW_MOBILE_MONEY_OPTION,
        planIds: { monthly: env.FLW_PLAN_ID_MONTHLY, quarterly: env.FLW_PLAN_ID_QUARTERLY, annual: env.FLW_PLAN_ID_ANNUAL },
        fetch: fetchImpl,
      }),
    );
  }
  if (wanted.has("wave") && env.WAVE_API_KEY) {
    providers.push(
      new WaveProvider({
        apiKey: env.WAVE_API_KEY,
        webhookSecret: required(env, "WAVE_WEBHOOK_SECRET"),
        baseUrl: env.WAVE_API_BASE_URL,
        fetch: fetchImpl,
      }),
    );
  }
  const routing: Partial<Record<PaymentMethod, ProviderId>> = {};
  if (env.PAYMENT_PROVIDER_CARD !== "none") routing.card = env.PAYMENT_PROVIDER_CARD;
  if (env.PAYMENT_PROVIDER_MOBILE_MONEY !== "none") routing.mobile_money = env.PAYMENT_PROVIDER_MOBILE_MONEY;
  return createRegistry(providers, routing);
}
