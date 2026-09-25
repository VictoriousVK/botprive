import "../fonts/fonts.css";
import "./globals.css";

import type { Metadata, Viewport } from "next";
import { Footer, Nav, Ticker } from "@/components/chrome";
import { SessionProvider } from "@/lib/session";

export const metadata: Metadata = {
  title: { default: "Liberté Financière — Robots de trading, académie et copytrading", template: "%s · Liberté Financière" },
  description: "Plateforme africaine de trading algorithmique pour MetaTrader 5 : robots ICT, formation vidéo, copytrading encadré, paiement Wave.",
  icons: { icon: "/brand/emblem.svg" },
  robots: { index: true, follow: true },
};

export const viewport: Viewport = { themeColor: "#03050a", width: "device-width", initialScale: 1 };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="fr">
      <body>
        <SessionProvider>
          <a href="#contenu" className="sr-only focus:not-sr-only focus:fixed focus:left-3 focus:top-3 focus:z-[100] focus:rounded-lg focus:bg-brand-500 focus:px-3 focus:py-2">
            Aller au contenu
          </a>
          <Ticker />
          <Nav />
          <main id="contenu">{children}</main>
          <Footer />
        </SessionProvider>
      </body>
    </html>
  );
}
