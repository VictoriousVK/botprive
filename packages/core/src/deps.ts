import type { Db } from "@vk/db";
import type { AppEnv } from "./config/env";
import type { Logger } from "./logger";
import type { ProviderRegistry } from "./payments/registry";

/** Dépendances communes au site et au worker. `now` est injecté pour tester le temps. */
export interface CoreDeps {
  db: Db;
  env: AppEnv;
  now: () => Date;
  logger: Logger;
  providers: ProviderRegistry;
}
