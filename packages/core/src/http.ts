import { ExternalServiceError } from "./errors";

export type FetchLike = typeof fetch;

export interface JsonRequest {
  method?: "GET" | "POST" | "PUT" | "DELETE" | "PATCH";
  headers?: Record<string, string>;
  body?: unknown;
  timeoutMs?: number;
}

/**
 * Appel JSON vers un service externe. Les erreurs réseau, 429 et 5xx sont marquées
 * « transitoires » (à réessayer). Le corps des erreurs est tronqué et ne contient pas nos en-têtes.
 */
export async function requestJson<T = unknown>(
  service: string,
  url: string,
  request: JsonRequest = {},
  fetchImpl: FetchLike = fetch,
): Promise<{ status: number; data: T }> {
  let response: Response;
  try {
    response = await fetchImpl(url, {
      method: request.method ?? "GET",
      headers: {
        accept: "application/json",
        ...(request.body !== undefined ? { "content-type": "application/json" } : {}),
        ...request.headers,
      },
      body: request.body !== undefined ? JSON.stringify(request.body) : undefined,
      signal: AbortSignal.timeout(request.timeoutMs ?? 15_000),
    });
  } catch (error) {
    throw new ExternalServiceError(service, `réseau indisponible (${error instanceof Error ? error.message : String(error)})`, true);
  }
  const text = await response.text();
  let data: unknown = null;
  if (text) {
    try {
      data = JSON.parse(text);
    } catch {
      data = { raw: text.slice(0, 500) };
    }
  }
  if (!response.ok) {
    const transient = response.status === 429 || response.status >= 500;
    const detail = typeof data === "object" && data && "message" in data ? String((data as { message: unknown }).message) : text.slice(0, 200);
    throw new ExternalServiceError(service, `HTTP ${response.status} ${detail}`, transient, response.status);
  }
  return { status: response.status, data: data as T };
}
