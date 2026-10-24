import type { Metadata, Viewport } from "next";
import "@fontsource/anton/400.css";
import "@fontsource/archivo/400.css";
import "@fontsource/archivo/600.css";
import "@fontsource/jetbrains-mono/400.css";
import "@fontsource/jetbrains-mono/700.css";
import "./globals.css";
import { loadEnv } from "@vk/core";
import { SiteFooter } from "@/components/SiteFooter";
import { SiteHeader } from "@/components/SiteHeader";

export const metadata: Metadata = {
  title: {
    default: "V_ICT_ORIOUS Live Club · Live trading Nasdaq & Gold",
    template: "%s · V_ICT_ORIOUS Live Club",
  },
  description:
    "Le Live Club de Victor Faye, trader ICT : 3 lives par semaine sur Discord (Nasdaq, Gold), Q&A, invité spécial chaque semaine, Telegram privé et stratégies Gold exclusives.",
  openGraph: {
    title: "V_ICT_ORIOUS Live Club",
    description: "Live · Q&A · Débrief. Nasdaq et Gold en direct, mardi, mercredi et vendredi.",
    locale: "fr_SN",
    type: "website",
  },
};

export const viewport: Viewport = {
  themeColor: "#08070c",
  width: "device-width",
  initialScale: 1,
};

// Rendu à la demande : réglages (tarifs, horaires, Telegram) et mode de paiement lus à l'exécution.
export const dynamic = "force-dynamic";

export default function RootLayout({ children }: { children: React.ReactNode }) {
  const testMode = loadEnv().PAYMENT_MODE !== "live";
  return (
    <html lang="fr">
      <body>
        <a className="skip-link" href="#contenu">
          Aller au contenu
        </a>
        {testMode ? <div className="test-banner">Mode test · aucun paiement réel n'est encaissé</div> : null}
        <SiteHeader />
        <main id="contenu">{children}</main>
        <SiteFooter />
      </body>
    </html>
  );
}
