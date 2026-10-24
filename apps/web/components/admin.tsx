import Link from "next/link";
import { readFlash } from "@/lib/admin";
import { FlashClear } from "./FlashClear";

export const ADMIN_LINKS = [
  { href: "/admin", label: "Vue d'ensemble" },
  { href: "/admin/tarifs", label: "Tarifs" },
  { href: "/admin/lives", label: "Lives" },
  { href: "/admin/telegram", label: "Telegram" },
  { href: "/admin/discord", label: "Discord" },
  { href: "/admin/membres", label: "Membres" },
  { href: "/admin/paiements", label: "Paiements" },
  { href: "/admin/import", label: "Import CSV" },
  { href: "/admin/journal", label: "Journal" },
];

export function AdminDenied({ loggedIn }: { loggedIn: boolean }) {
  return (
    <div className="container page page-narrow">
      <p className="label">Administration</p>
      <h1 className="display" style={{ fontSize: "clamp(2.4rem, 10vw, 4rem)" }}>
        Accès réservé
      </h1>
      {loggedIn ? (
        <p className="lead">Ton compte Discord n'est pas autorisé. Son identifiant doit figurer dans ADMIN_DISCORD_IDS (variables d'environnement).</p>
      ) : (
        <>
          <p className="lead">Connecte-toi avec ton compte Discord administrateur.</p>
          <a className="btn" href="/api/auth/discord/login?next=%2Fadmin">
            Se connecter avec Discord
          </a>
        </>
      )}
    </div>
  );
}

export async function AdminPage({ title, intro, children }: { title: string; intro?: React.ReactNode; children: React.ReactNode }) {
  const flash = await readFlash();
  return (
    <div className="container page admin">
      <nav className="admin-nav" aria-label="Tableau de bord">
        {ADMIN_LINKS.map((l) => (
          <Link key={l.href} href={l.href}>
            {l.label}
          </Link>
        ))}
      </nav>
      <p className="label">Tableau de bord</p>
      <h1 className="display admin-title">{title}</h1>
      {intro ? <div className="lead admin-intro">{intro}</div> : null}
      {flash ? (
        <>
          <p className={`alert ${flash.type === "ok" ? "success" : "error"}`} role={flash.type === "ok" ? "status" : "alert"}>
            {flash.text}
          </p>
          <FlashClear />
        </>
      ) : null}
      {children}
    </div>
  );
}

export function Pill({ tone, children }: { tone: "ok" | "warn" | "off"; children: React.ReactNode }) {
  return <span className={`status ${tone}`}>{children}</span>;
}
