import { drizzle } from "drizzle-orm/postgres-js";
import type { PgDatabase, PgQueryResultHKT } from "drizzle-orm/pg-core";
import postgres from "postgres";
import * as schema from "./schema";

export type Schema = typeof schema;
/** Base ou transaction : les fonctions métier acceptent les deux. */
export type Db = PgDatabase<PgQueryResultHKT, Schema>;

export interface DbHandle {
  db: Db;
  close: () => Promise<void>;
}

export function createDb(url: string, options: { max?: number } = {}): DbHandle {
  const client = postgres(url, {
    max: options.max ?? 10,
    // Les montants XOF tiennent dans un integer ; bigserial est lu en number (voir schema).
    onnotice: () => {},
  });
  const db = drizzle(client, { schema }) as unknown as Db;
  return { db, close: () => client.end({ timeout: 5 }) };
}
