import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import { signWavePayload } from "../payments/providers/wave";
import { paydunyaHash } from "../payments/providers/paydunya";

/*
 * Faux serveur Flutterwave + Wave, pour développer et tester SANS vrai paiement.
 * Il reproduit le sous-ensemble d'API utilisé par l'application (formats des docs officielles)
 * et sert une page de paiement factice avec les boutons « Payer » / « Refuser ».
 * Il ne remplace pas les tests en sandbox réelle (phase 5).
 */

export interface MockProvidersConfig {
  flwSecretKey: string;
  flwWebhookHash: string;
  waveApiKey: string;
  waveWebhookSecret: string;
  paydunyaMasterKey?: string;
  paydunyaPrivateKey?: string;
  paydunyaToken?: string;
  /** URL de l'application qui reçoit les webhooks (…/api/webhooks/{provider}). Optionnel. */
  webhookBaseUrl?: string;
  now?: () => Date;
}

export interface FlwTx {
  id: number;
  tx_ref: string;
  amount: number;
  currency: string;
  status: "pending" | "successful" | "failed";
  payment_type: string;
  plan: number | null;
  customer: { email: string };
  redirect_url: string;
}

export interface FlwSub {
  id: number;
  plan: number;
  status: "active" | "cancelled";
  customer: { customer_email: string };
  transaction_id: number;
  amount: number;
}

export interface WaveSessionMock {
  id: string;
  amount: string;
  currency: string;
  client_reference: string;
  checkout_status: "open" | "complete" | "expired";
  payment_status: "processing" | "succeeded" | "cancelled";
  transaction_id: string | null;
  success_url: string;
  error_url: string;
  wave_launch_url: string;
}

export interface PayDunyaInvoiceMock {
  token: string;
  total_amount: number;
  custom_data: Record<string, unknown>;
  actions: { return_url?: string; cancel_url?: string; callback_url?: string };
  status: "pending" | "completed" | "cancelled";
  channels?: string[];
}

type MockProvider = "flutterwave" | "wave" | "paydunya";

export interface WebhookDelivery {
  provider: MockProvider;
  headers: Record<string, string>;
  rawBody: string;
}

function readBody(req: IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    let data = "";
    req.on("data", (c) => (data += c));
    req.on("end", () => resolve(data));
    req.on("error", reject);
  });
}

function json(res: ServerResponse, status: number, body: unknown): void {
  res.writeHead(status, { "content-type": "application/json" });
  res.end(JSON.stringify(body));
}

export class MockProviders {
  readonly flwTransactions = new Map<number, FlwTx>();
  readonly flwSubscriptions = new Map<number, FlwSub>();
  readonly waveSessions = new Map<string, WaveSessionMock>();
  readonly paydunyaInvoices = new Map<string, PayDunyaInvoiceMock>();
  readonly deliveries: WebhookDelivery[] = [];
  private server: Server | null = null;
  private nextId = 9_000_001;
  baseUrl = "";

  constructor(private readonly config: MockProvidersConfig) {}

  private now(): Date {
    return this.config.now ? this.config.now() : new Date();
  }

  async start(port = 0): Promise<string> {
    this.server = createServer((req, res) => {
      this.route(req, res).catch((error) => json(res, 500, { status: "error", message: String(error) }));
    });
    await new Promise<void>((resolve) => this.server!.listen(port, "127.0.0.1", resolve));
    const address = this.server.address() as AddressInfo;
    this.baseUrl = `http://127.0.0.1:${address.port}`;
    return this.baseUrl;
  }

  async stop(): Promise<void> {
    if (this.server) await new Promise<void>((resolve) => this.server!.close(() => resolve()));
  }

  // ─── Actions pilotées (tests, simulation) ───────────────────────────────

  /** Le client valide le paiement. Retourne le webhook à livrer. */
  pay(provider: MockProvider, reference: string): WebhookDelivery {
    if (provider === "paydunya") return this.paydunyaIpn(this.paydunyaByRef(reference), "completed");
    if (provider === "flutterwave") {
      const tx = [...this.flwTransactions.values()].find((t) => t.tx_ref === reference);
      if (!tx) throw new Error(`Transaction Flutterwave inconnue : ${reference}`);
      tx.status = "successful";
      if (tx.plan) {
        const id = this.nextId++;
        this.flwSubscriptions.set(id, { id, plan: tx.plan, status: "active", customer: { customer_email: tx.customer.email }, transaction_id: tx.id, amount: tx.amount });
      }
      return this.flutterwaveChargeWebhook(tx);
    }
    const session = [...this.waveSessions.values()].find((s) => s.client_reference === reference);
    if (!session) throw new Error(`Session Wave inconnue : ${reference}`);
    session.checkout_status = "complete";
    session.payment_status = "succeeded";
    session.transaction_id = `T_${this.nextId++}`;
    return this.waveWebhook(session, "checkout.session.completed");
  }

  /** Le client refuse / échoue le paiement. */
  fail(provider: MockProvider, reference: string): WebhookDelivery {
    if (provider === "paydunya") return this.paydunyaIpn(this.paydunyaByRef(reference), "cancelled");
    if (provider === "flutterwave") {
      const tx = [...this.flwTransactions.values()].find((t) => t.tx_ref === reference);
      if (!tx) throw new Error(`Transaction Flutterwave inconnue : ${reference}`);
      tx.status = "failed";
      return this.flutterwaveChargeWebhook(tx);
    }
    const session = [...this.waveSessions.values()].find((s) => s.client_reference === reference);
    if (!session) throw new Error(`Session Wave inconnue : ${reference}`);
    session.checkout_status = "expired";
    session.payment_status = "cancelled";
    return this.waveWebhook(session, "checkout.session.payment_failed");
  }

  /** Prélèvement automatique d'un abonnement carte (nouvelle transaction, même tx_ref). */
  chargeRecurring(subscriptionId: number, outcome: "successful" | "failed" = "successful"): WebhookDelivery {
    const sub = this.flwSubscriptions.get(subscriptionId);
    if (!sub || sub.status !== "active") throw new Error(`Abonnement Flutterwave inactif : ${subscriptionId}`);
    const first = this.flwTransactions.get(sub.transaction_id)!;
    const id = this.nextId++;
    const tx: FlwTx = { ...first, id, status: outcome };
    this.flwTransactions.set(id, tx);
    return this.flutterwaveChargeWebhook(tx);
  }

  cancelledSubscriptionWebhook(subscriptionId: number): WebhookDelivery {
    const sub = this.flwSubscriptions.get(subscriptionId)!;
    sub.status = "cancelled";
    return this.flutterwaveWebhook({ event: "subscription.cancelled", data: { id: sub.id, status: "cancelled", customer: { email: sub.customer.customer_email }, plan: sub.plan } });
  }

  flutterwaveChargeWebhook(tx: FlwTx): WebhookDelivery {
    return this.flutterwaveWebhook({
      event: "charge.completed",
      data: { id: tx.id, tx_ref: tx.tx_ref, amount: tx.amount, currency: tx.currency, status: tx.status, payment_type: tx.payment_type, customer: tx.customer },
    });
  }

  private flutterwaveWebhook(body: unknown): WebhookDelivery {
    const delivery = { provider: "flutterwave" as const, headers: { "verif-hash": this.config.flwWebhookHash }, rawBody: JSON.stringify(body) };
    this.deliveries.push(delivery);
    return delivery;
  }

  waveWebhook(session: WaveSessionMock, type: string): WebhookDelivery {
    const rawBody = JSON.stringify({ id: `EV_${this.nextId++}`, type, data: session });
    const delivery = { provider: "wave" as const, headers: { "wave-signature": signWavePayload(rawBody, this.config.waveWebhookSecret, this.now()) }, rawBody };
    this.deliveries.push(delivery);
    return delivery;
  }

  private paydunyaByRef(reference: string): PayDunyaInvoiceMock {
    const invoice = [...this.paydunyaInvoices.values()].find((i) => i.custom_data.reference === reference);
    if (!invoice) throw new Error(`Facture PayDunya inconnue : ${reference}`);
    return invoice;
  }

  /** IPN PayDunya (formulaire data[...]) avec le hash SHA-512 de la clé principale. */
  paydunyaIpn(invoice: PayDunyaInvoiceMock, status: "completed" | "cancelled", masterKey = this.config.paydunyaMasterKey ?? "pd-master-test"): WebhookDelivery {
    invoice.status = status;
    const form = new URLSearchParams({
      "data[hash]": paydunyaHash(masterKey),
      "data[status]": status,
      "data[invoice][token]": invoice.token,
      "data[invoice][total_amount]": String(invoice.total_amount),
      "data[custom_data][reference]": String(invoice.custom_data.reference ?? ""),
    });
    const delivery = { provider: "paydunya" as const, headers: { "content-type": "application/x-www-form-urlencoded" }, rawBody: form.toString() };
    this.deliveries.push(delivery);
    return delivery;
  }

  /** Envoie le webhook à l'application (si webhookBaseUrl est configurée). */
  async deliver(delivery: WebhookDelivery): Promise<number> {
    if (!this.config.webhookBaseUrl) return 0;
    const res = await fetch(`${this.config.webhookBaseUrl.replace(/\/$/, "")}/api/webhooks/${delivery.provider}`, {
      method: "POST",
      headers: { "content-type": "application/json", ...delivery.headers },
      body: delivery.rawBody,
    });
    return res.status;
  }

  // ─── API HTTP imitée ─────────────────────────────────────────────────────

  private async route(req: IncomingMessage, res: ServerResponse): Promise<void> {
    const url = new URL(req.url ?? "/", "http://mock");
    const path = url.pathname;
    const method = req.method ?? "GET";
    const auth = req.headers.authorization ?? "";

    // Pages de paiement factices
    const page = /^\/mock\/checkout\/(flutterwave|wave|paydunya)\/([^/]+)(?:\/(pay|fail))?$/.exec(path);
    if (page) return this.checkoutPage(req, res, page[1] as MockProvider, decodeURIComponent(page[2]!), page[3] as "pay" | "fail" | undefined);

    const pd = /^\/(?:sandbox-api|api)\/v1\/(.*)$/.exec(path);
    if (pd) {
      const ok =
        req.headers["paydunya-master-key"] === (this.config.paydunyaMasterKey ?? "pd-master-test") &&
        req.headers["paydunya-private-key"] === (this.config.paydunyaPrivateKey ?? "test_private_mock") &&
        req.headers["paydunya-token"] === (this.config.paydunyaToken ?? "pd-token-test");
      if (!ok) return json(res, 200, { response_code: "1001", response_text: "Invalid Masterkey Specified" });
      return this.paydunya(req, res, method, pd[1]!);
    }

    if (path.startsWith("/v3/")) {
      if (auth !== `Bearer ${this.config.flwSecretKey}`) return json(res, 401, { status: "error", message: "Invalid authorization key" });
      return this.flutterwave(req, res, method, path, url);
    }
    if (path.startsWith("/v1/")) {
      if (auth !== `Bearer ${this.config.waveApiKey}`) return json(res, 401, { code: "invalid-auth", message: "Invalid API key" });
      return this.wave(req, res, method, path);
    }
    json(res, 404, { message: "not found" });
  }

  private async flutterwave(req: IncomingMessage, res: ServerResponse, method: string, path: string, url: URL): Promise<void> {
    if (method === "POST" && path === "/v3/payments") {
      const body = JSON.parse(await readBody(req));
      const id = this.nextId++;
      const tx: FlwTx = {
        id,
        tx_ref: body.tx_ref,
        amount: Number(body.amount),
        currency: body.currency,
        status: "pending",
        payment_type: body.payment_options === "card" ? "card" : "mobilemoneyfranco",
        plan: body.payment_plan ? Number(body.payment_plan) : null,
        customer: { email: body.customer?.email },
        redirect_url: body.redirect_url,
      };
      this.flwTransactions.set(id, tx);
      return json(res, 200, { status: "success", message: "Hosted Link", data: { link: `${this.baseUrl}/mock/checkout/flutterwave/${encodeURIComponent(tx.tx_ref)}` } });
    }
    if (method === "POST" && path === "/v3/payment-plans") {
      const body = JSON.parse(await readBody(req));
      return json(res, 200, { status: "success", message: "Payment plan created", data: { id: this.nextId++, ...body, status: "active" } });
    }
    let m = /^\/v3\/transactions\/(\d+)\/verify$/.exec(path);
    if (method === "GET" && m) {
      const tx = this.flwTransactions.get(Number(m[1]));
      return tx ? json(res, 200, { status: "success", data: tx }) : json(res, 400, { status: "error", message: "No transaction was found for this id" });
    }
    if (method === "GET" && path === "/v3/transactions/verify_by_reference") {
      const ref = url.searchParams.get("tx_ref");
      const matches = [...this.flwTransactions.values()].filter((t) => t.tx_ref === ref);
      const tx = matches[matches.length - 1];
      return tx ? json(res, 200, { status: "success", data: tx }) : json(res, 400, { status: "error", message: "No transaction was found" });
    }
    if (method === "GET" && path === "/v3/subscriptions") {
      const txId = url.searchParams.get("transaction_id");
      const email = url.searchParams.get("email");
      const list = [...this.flwSubscriptions.values()].filter(
        (s) => (!txId || String(s.transaction_id) === txId) && (!email || s.customer.customer_email === email),
      );
      return json(res, 200, { status: "success", data: list });
    }
    m = /^\/v3\/subscriptions\/(\d+)\/cancel$/.exec(path);
    if (method === "PUT" && m) {
      const sub = this.flwSubscriptions.get(Number(m[1]));
      if (!sub) return json(res, 404, { status: "error", message: "Subscription not found" });
      sub.status = "cancelled";
      return json(res, 200, { status: "success", message: "Subscription cancelled", data: sub });
    }
    m = /^\/v3\/transactions\/(\d+)\/refund$/.exec(path);
    if (method === "POST" && m) return json(res, 200, { status: "success", data: { status: "completed" } });
    json(res, 404, { status: "error", message: "not found" });
  }

  private async wave(req: IncomingMessage, res: ServerResponse, method: string, path: string): Promise<void> {
    if (method === "POST" && path === "/v1/checkout/sessions") {
      const body = JSON.parse(await readBody(req));
      const id = `cos-${(this.nextId++).toString(36)}`;
      const session: WaveSessionMock = {
        id,
        amount: String(body.amount),
        currency: body.currency,
        client_reference: body.client_reference,
        checkout_status: "open",
        payment_status: "processing",
        transaction_id: null,
        success_url: body.success_url,
        error_url: body.error_url,
        wave_launch_url: `${this.baseUrl}/mock/checkout/wave/${encodeURIComponent(body.client_reference)}`,
      };
      this.waveSessions.set(id, session);
      return json(res, 200, session);
    }
    let m = /^\/v1\/checkout\/sessions\/([^/]+)$/.exec(path);
    if (method === "GET" && m) {
      const s = this.waveSessions.get(m[1]!);
      return s ? json(res, 200, s) : json(res, 404, { code: "not-found", message: "Checkout session not found" });
    }
    m = /^\/v1\/checkout\/sessions\/([^/]+)\/refund$/.exec(path);
    if (method === "POST" && m) return json(res, 200, {});
    json(res, 404, { message: "not found" });
  }

  private async paydunya(req: IncomingMessage, res: ServerResponse, method: string, path: string): Promise<void> {
    if (method === "POST" && path === "checkout-invoice/create") {
      const body = JSON.parse(await readBody(req));
      const token = `test_${(this.nextId++).toString(36)}`;
      const invoice: PayDunyaInvoiceMock = {
        token,
        total_amount: Number(body.invoice?.total_amount),
        custom_data: body.custom_data ?? {},
        actions: body.actions ?? {},
        status: "pending",
        channels: body.channels,
      };
      this.paydunyaInvoices.set(token, invoice);
      return json(res, 200, { response_code: "00", response_text: `${this.baseUrl}/mock/checkout/paydunya/${encodeURIComponent(String(invoice.custom_data.reference))}`, description: "Checkout Invoice Created", token });
    }
    const m = /^checkout-invoice\/confirm\/([^/]+)$/.exec(path);
    if (method === "GET" && m) {
      const invoice = this.paydunyaInvoices.get(m[1]!);
      if (!invoice) return json(res, 200, { response_code: "1004", response_text: "Invoice Not Found" });
      return json(res, 200, {
        response_code: "00",
        response_text: "Transaction Found",
        hash: paydunyaHash(this.config.paydunyaMasterKey ?? "pd-master-test"),
        invoice: { token: invoice.token, total_amount: String(invoice.total_amount) },
        custom_data: invoice.custom_data,
        actions: invoice.actions,
        mode: "test",
        status: invoice.status,
      });
    }
    json(res, 404, { response_code: "404", response_text: "not found" });
  }

  private async checkoutPage(req: IncomingMessage, res: ServerResponse, provider: MockProvider, reference: string, action?: "pay" | "fail"): Promise<void> {
    const back = (() => {
      if (provider === "paydunya") {
        const invoice = [...this.paydunyaInvoices.values()].find((i) => i.custom_data.reference === reference);
        return action === "fail" ? invoice?.actions.cancel_url : invoice?.actions.return_url;
      }
      if (provider === "flutterwave") return [...this.flwTransactions.values()].find((t) => t.tx_ref === reference)?.redirect_url;
      const s = [...this.waveSessions.values()].find((x) => x.client_reference === reference);
      return action === "fail" ? s?.error_url : s?.success_url;
    })();
    if (action && req.method === "POST") {
      const delivery = action === "pay" ? this.pay(provider, reference) : this.fail(provider, reference);
      await this.deliver(delivery).catch(() => 0);
      const target = provider === "flutterwave" && back ? `${back}&status=${action === "pay" ? "successful" : "failed"}` : back;
      res.writeHead(303, { location: target ?? "/" });
      res.end();
      return;
    }
    res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
    res.end(`<!doctype html><html lang="fr"><meta name="viewport" content="width=device-width,initial-scale=1">
<body style="font-family:system-ui;background:#111;color:#eee;display:grid;place-items:center;min-height:100vh;margin:0">
<main style="max-width:420px;padding:24px;border:1px solid #444;border-radius:12px">
<p style="color:#f2b732;font-size:12px;letter-spacing:2px">PAIEMENT FACTICE · ${provider.toUpperCase()} (MOCK LOCAL)</p>
<h1 style="font-size:20px">Référence ${reference}</h1>
<p>Aucun argent réel n'est débité. Choisis l'issue du paiement :</p>
<form method="post" action="/mock/checkout/${provider}/${encodeURIComponent(reference)}/pay"><button style="padding:12px 20px;font-size:16px">Payer</button></form>
<form method="post" action="/mock/checkout/${provider}/${encodeURIComponent(reference)}/fail" style="margin-top:12px"><button style="padding:12px 20px">Refuser</button></form>
</main></body></html>`);
  }
}
