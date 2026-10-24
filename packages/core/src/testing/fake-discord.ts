import { ExternalServiceError } from "../errors";
import type { DiscordGateway, GuildMemberInfo } from "../discord/access";

/** Discord en mémoire pour les tests et la simulation. `down = true` simule une panne. */
export class FakeDiscord implements DiscordGateway {
  readonly members = new Map<string, GuildMemberInfo>();
  readonly dms: { userId: string; content: string }[] = [];
  readonly logs: string[] = [];
  readonly kicked: string[] = [];
  readonly blockedDms = new Set<string>();
  down = false;
  calls = 0;

  constructor(private readonly onLog?: (content: string) => void) {}

  join(userId: string, roles: string[] = [], options: { isBot?: boolean } = {}): void {
    this.members.set(userId, { userId, roles: [...roles], isBot: options.isBot });
  }

  rolesOf(userId: string): string[] {
    return this.members.get(userId)?.roles ?? [];
  }

  private check(): void {
    this.calls++;
    if (this.down) throw new ExternalServiceError("Discord", "service indisponible (simulé)", true, 503);
  }

  async getMember(userId: string) {
    this.check();
    const m = this.members.get(userId);
    return m ? { ...m, roles: [...m.roles] } : null;
  }

  async listMembers() {
    this.check();
    return [...this.members.values()].map((m) => ({ ...m, roles: [...m.roles] }));
  }

  async addRole(userId: string, roleId: string) {
    this.check();
    const m = this.members.get(userId);
    if (!m) throw new ExternalServiceError("Discord", "Unknown Member", false, 404);
    if (!m.roles.includes(roleId)) m.roles.push(roleId);
  }

  async removeRole(userId: string, roleId: string) {
    this.check();
    const m = this.members.get(userId);
    if (m) m.roles = m.roles.filter((r) => r !== roleId);
  }

  async kick(userId: string) {
    this.check();
    this.members.delete(userId);
    this.kicked.push(userId);
  }

  async sendDm(userId: string, content: string) {
    this.check();
    if (this.blockedDms.has(userId)) return "blocked" as const;
    this.dms.push({ userId, content });
    return "sent" as const;
  }

  async postLog(content: string) {
    this.check();
    this.logs.push(content);
    this.onLog?.(content);
  }
}
