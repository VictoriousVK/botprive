"use client";

import { MotionConfig } from "framer-motion";
import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import { api, setCsrf, type Me, type SiteInfo } from "./api";

type Ctx = {
  site: SiteInfo | null;
  me: Me | null;
  ready: boolean; // the member session has been checked
  refreshMe: () => Promise<Me | null>;
  setMe: (m: Me | null) => void;
};

const SessionCtx = createContext<Ctx>({ site: null, me: null, ready: false, refreshMe: async () => null, setMe: () => {} });

export function SessionProvider({ children }: { children: ReactNode }) {
  const [site, setSite] = useState<SiteInfo | null>(null);
  const [me, setMeState] = useState<Me | null>(null);
  const [ready, setReady] = useState(false);

  const setMe = useCallback((m: Me | null) => {
    if (m?.csrf) setCsrf("member", m.csrf);
    if (!m) setCsrf("member", "");
    setMeState(m);
  }, []);

  const refreshMe = useCallback(async () => {
    try {
      const { member } = await api<{ member: Me | null }>("/api/m/session");
      setMe(member);
      return member;
    } catch {
      return null;
    } finally {
      setReady(true);
    }
  }, [setMe]);

  useEffect(() => {
    api<SiteInfo>("/api/site")
      .then((info) => {
        setSite(info);
        if (info.sentry) startSentry(info.sentry);
      })
      .catch(() => setSite(null));
    refreshMe();
  }, [refreshMe]);

  const value = useMemo(() => ({ site, me, ready, refreshMe, setMe }), [site, me, ready, refreshMe, setMe]);
  return (
    <SessionCtx.Provider value={value}>
      <MotionConfig reducedMotion="user">{children}</MotionConfig>
    </SessionCtx.Provider>
  );
}

export const useSession = () => useContext(SessionCtx);

// Error reporting for the pages (only when the server sets SENTRY_BROWSER_DSN). Loaded on
// demand, so visitors download nothing extra when it is off. No personal data is sent.
let sentryStarted = false;
function startSentry(cfg: NonNullable<SiteInfo["sentry"]>) {
  if (sentryStarted) return;
  sentryStarted = true;
  import("@sentry/browser")
    .then((Sentry) => {
      Sentry.init({
        dsn: cfg.dsn,
        environment: cfg.environment,
        release: cfg.release,
        sendDefaultPii: false,
        tracesSampleRate: 0,
        beforeSend(event) {
          if (event.request?.url) event.request.url = event.request.url.split("?")[0]; // e-mail links carry tokens
          if (event.request?.query_string) delete event.request.query_string;
          return event;
        },
        beforeBreadcrumb(b) {
          if (typeof b.data?.url === "string") b.data.url = b.data.url.split("?")[0];
          if (typeof b.data?.to === "string") b.data.to = b.data.to.split("?")[0];
          if (typeof b.data?.from === "string") b.data.from = b.data.from.split("?")[0];
          return b;
        },
      });
    })
    .catch(() => {});
}

export function useApi<T>(path: string | null, deps: unknown[] = []) {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(!!path);
  const load = useCallback(async () => {
    if (!path) return;
    setLoading(true);
    try {
      setData(await api<T>(path));
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Erreur");
    } finally {
      setLoading(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [path, ...deps]);
  useEffect(() => {
    load();
  }, [load]);
  return { data, error, loading, reload: load, setData };
}
