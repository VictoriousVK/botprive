import { createHash } from "node:crypto";
import { safeEqual } from "../../crypto";
import { InvalidSignatureError, UnsupportedOperationError } from "../../errors";
import { requestJson, type FetchLike } from "../../http";
import type {
  CheckoutRequest,
  CheckoutSession,
  NormalizedWebhookEvent,
  PaymentProvider,
  ProviderSubscriptionStatus,
  RefundRequest,
  VerifiedPayment,
  VerifiedStatus,
  VerifyRequest,
  WebhookRequest,
} from "../types";

/*
 * PayDunya : facture avec redirection (« checkout-invoice »), carte et Mobile Money
 * (Orange Money, Wave, Free Money…). Pas d'abonnement ni de prélèvement automatique documenté :
 * renouvellement assisté uniquement (lien de paiement à chaque échéance).
 *
 * IPN : PayDunya envoie data.hash = SHA-512 de la clé principale. C'est une valeur constante, pas une
 * signature du contenu : chaque notification est donc re-vérifiée via /checkout-invoice/confirm/{token}.
 * Points à confirmer en sandbox : format exact de l'IPN (formulaire ou JSON) et paramètre « channels ».
 */

export const PAYDUNYA_LIVE_URL = "https://app.paydunya.com/api/v1";
export const PAYDUNYA_SANDBOX_URL = "https://app.paydunya.com/sandbox-api/v1";

export interface PayDunyaConfig {
  masterKey: string;
  privateKey: string;
  token: string;
  baseUrl: string;
  /** URL publique de notre webhook (callback_url). */
  callbackUrl: string;
  storeName?: string;
  fetch?: FetchLike;
}

interface PayDunyaConfirm {
  response_code?: string;
  response_text?: string;
  status?: string;
  invoice?: { token?: string; total_amount?: string | number };
  custom_data?: { reference?: string } | Record<string, unknown>;
  mode?: string;
}

function mapStatus(status: string | undefined): VerifiedStatus {
  const s = (status ?? "").toLowerCase();
  if (s === "completed") return "succeeded";
  if (s === "cancelled" || s === "canceled" || s === "failed") return "failed";
  return "pending";
}

/** Clés de formulaire « data[invoice][token] » → objet imbriqué. */
function parseNestedForm(raw: string): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [key, value] of new URLSearchParams(raw)) {
    const path = key.replace(/\]/g, "").split("[");
    let node = out;
    path.forEach((part, i) => {
      if (i === path.length - 1) node[part] = value;
      else node = (node[part] ??= {}) as Record<string, unknown>;
    });
  }
  return out;
}

export function paydunyaHash(masterKey: string): string {
  return createHash("sha512").update(masterKey).digest("hex");
}

export class PayDunyaProvider implements PaymentProvider {
  readonly id = "paydunya" as const;
  readonly capabilities = { card: true, mobileMoney: true, recurring: false, refund: false };
  readonly testMode: boolean;
  private readonly fetchImpl: FetchLike;

  constructor(private readonly config: PayDunyaConfig) {
    this.fetchImpl = config.fetch ?? fetch;
    this.testMode = config.baseUrl !== PAYDUNYA_LIVE_URL || config.privateKey.startsWith("test_");
  }

  private call<T>(path: string, init: { method?: "GET" | "POST"; body?: unknown } = {}) {
    return requestJson<T>(
      "PayDunya",
      `${this.config.baseUrl}${path}`,
      {
        method: init.method,
        body: init.body,
        headers: {
          "paydunya-master-key": this.config.masterKey,
          "paydunya-private-key": this.config.privateKey,
          "paydunya-token": this.config.token,
        },
      },
      this.fetchImpl,
    );
  }

  async createCheckout(request: CheckoutRequest): Promise<CheckoutSession> {
    if (request.autoRenew) throw new UnsupportedOperationError("paydunya", "renouvellement automatique");
    const channels = request.method === "card" ? ["card"] : ["orange-money-senegal", "wave-senegal", "free-money-senegal"];
    const { data } = await this.call<{ response_code?: string; response_text?: string; token?: string; description?: string }>(
      "/checkout-invoice/create",
      {
        method: "POST",
        body: {
          invoice: {
            total_amount: request.amount,
            description: `V_ICT_ORIOUS Live Club · formule ${request.plan.label}`,
            items: { item_0: { name: `Formule ${request.plan.label}`, quantity: 1, unit_price: request.amount, total_price: request.amount } },
          },
          store: { name: this.config.storeName ?? "V_ICT_ORIOUS Live Club" },
          actions: { return_url: request.returnUrl, cancel_url: request.cancelUrl, callback_url: this.config.callbackUrl },
          custom_data: { reference: request.reference, plan_id: request.plan.id, discord_user_id: request.customer.discordUserId },
          channels,
        },
      },
    );
    if (data.response_code !== "00" || !data.response_text || !data.token) {
      throw new Error(`PayDunya a refusé la facture (${data.response_code ?? "?"} ${data.description ?? data.response_text ?? ""})`);
    }
    return { redirectUrl: data.response_text, providerCheckoutId: data.token };
  }

  async verifyPayment(request: VerifyRequest): Promise<VerifiedPayment> {
    if (!request.providerCheckoutId) throw new Error("Vérification PayDunya : jeton de facture requis");
    const { data } = await this.call<PayDunyaConfirm>(`/checkout-invoice/confirm/${encodeURIComponent(request.providerCheckoutId)}`);
    const reference = (data.custom_data as { reference?: string } | undefined)?.reference;
    return {
      status: data.response_code === "00" ? mapStatus(data.status) : "pending",
      reference,
      amount: Number(data.invoice?.total_amount ?? 0),
      currency: "XOF",
      providerTransactionId: data.invoice?.token ?? request.providerCheckoutId,
      raw: { response_code: data.response_code, status: data.status, token: data.invoice?.token, total_amount: data.invoice?.total_amount, reference, mode: data.mode },
    };
  }

  async handleWebhook(request: WebhookRequest): Promise<NormalizedWebhookEvent> {
    let body: Record<string, unknown>;
    const contentType = request.headers["content-type"] ?? "";
    try {
      body = contentType.includes("json") ? JSON.parse(request.rawBody) : parseNestedForm(request.rawBody);
    } catch {
      throw new InvalidSignatureError("Corps IPN illisible");
    }
    const data = (body.data ?? body) as { hash?: string; status?: string; invoice?: { token?: string }; custom_data?: { reference?: string } };
    if (!data.hash || !safeEqual(String(data.hash), paydunyaHash(this.config.masterKey))) {
      throw new InvalidSignatureError("Hash PayDunya absent ou invalide");
    }
    const token = data.invoice?.token;
    return {
      kind: "payment",
      eventType: `ipn.${data.status ?? "unknown"}`,
      eventKey: `ipn:${token ?? "?"}:${data.status ?? ""}`,
      reference: data.custom_data?.reference,
      providerCheckoutId: token,
      providerTransactionId: token,
      hintedStatus: mapStatus(data.status),
      payload: { status: data.status, token, reference: data.custom_data?.reference },
    };
  }

  async cancelSubscription(): Promise<void> {
    throw new UnsupportedOperationError("paydunya", "annulation d'abonnement (pas d'abonnement chez PayDunya)");
  }

  async getSubscriptionStatus(): Promise<ProviderSubscriptionStatus> {
    throw new UnsupportedOperationError("paydunya", "statut d'abonnement (pas d'abonnement chez PayDunya)");
  }

  async refund(_request: RefundRequest): Promise<{ status: "succeeded" | "pending" }> {
    throw new UnsupportedOperationError("paydunya", "remboursement par API (à faire depuis le tableau de bord PayDunya)");
  }
}
