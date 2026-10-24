import type { EmailMessage, EmailSender } from "../notifications/email";

export class MemoryEmailSender implements EmailSender {
  readonly sent: EmailMessage[] = [];
  async send(message: EmailMessage): Promise<void> {
    this.sent.push(message);
  }
}
