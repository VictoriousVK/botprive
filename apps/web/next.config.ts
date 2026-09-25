import type { NextConfig } from "next";

// Production: static export (out/), copied into hedgefund/web/site and served by the Python
// platform on the same origin as its API. Development: `npm run dev` proxies /api to the
// platform running on http://127.0.0.1:8000 (python -m hedgefund.web serve).
const dev = process.env.NODE_ENV !== "production";
const api = process.env.LF_API_ORIGIN || "http://127.0.0.1:8000";

const config: NextConfig = {
  trailingSlash: true,
  images: { unoptimized: true },
  poweredByHeader: false,
  devIndicators: false,
  ...(dev
    ? { rewrites: async () => [{ source: "/api/:path*", destination: `${api}/api/:path*` }, { source: "/console", destination: `${api}/console` }, { source: "/static/:path*", destination: `${api}/static/:path*` }] }
    : { output: "export" as const }),
};

export default config;
