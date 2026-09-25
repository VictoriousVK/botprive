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
    api<SiteInfo>("/api/site").then(setSite).catch(() => setSite(null));
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
