import type { AppEnv } from "../config/env";
import { required } from "../config/env";
import { requestJson, type FetchLike } from "../http";
import type { Logger } from "../logger";

export interface EmailMessage {
  to: string;
  subject: string;
  text: string;
  html: string;
}

export interface EmailSender {
  send(message: EmailMessage): Promise<void>;
}

/** Envoi via l'API HTTP de Resend. */
export class ResendEmailSender implements EmailSender {
  constructor(
    private readonly apiKey: string,
    private readonly from: string,
    private readonly replyTo?: string,
    private readonly fetchImpl: FetchLike = fetch,
  ) {}

  async send(message: EmailMessage): Promise<void> {
    await requestJson(
      "Resend",
      "https://api.resend.com/emails",
      {
        method: "POST",
        headers: { authorization: `Bearer ${this.apiKey}` },
        body: {
          from: this.from,
          to: [message.to],
          subject: message.subject,
          text: message.text,
          html: message.html,
          ...(this.replyTo ? { reply_to: this.replyTo } : {}),
        },
      },
      this.fetchImpl,
    );
  }
}

/** Développement : affiche l'email dans la console au lieu de l'envoyer. */
export class ConsoleEmailSender implements EmailSender {
  constructor(private readonly logger: Logger) {}

  async send(message: EmailMessage): Promise<void> {
    this.logger.info(`[email simulé] à ${message.to} · « ${message.subject} »\n${message.text}`);
  }
}

export function createEmailSender(env: AppEnv, logger: Logger): EmailSender {
  if (env.EMAIL_PROVIDER === "resend") {
    return new ResendEmailSender(required(env, "RESEND_API_KEY"), env.EMAIL_FROM, env.EMAIL_REPLY_TO);
  }
  return new ConsoleEmailSender(logger);
}
