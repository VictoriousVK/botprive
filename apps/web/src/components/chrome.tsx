"use client";

import { AnimatePresence, motion } from "framer-motion";
import { ArrowUpRight, Menu, TrendingDown, TrendingUp, User, X } from "lucide-react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import { api, pct, price, type Quotes } from "@/lib/api";
import { useSession } from "@/lib/session";
import { Emblem, Lockup, VFMark, Wordmark } from "./brand";

const LINKS = [
  { href: "/robots/", label: "Robots" },
  { href: "/copytrading/", label: "Copytrading" },
  { href: "/academie/", label: "Académie" },
  { href: "/tarifs/", label: "Offres" },
];

export function Ticker() {
  const [q, setQ] = useState<Quotes | null>(null);
  useEffect(() => {
    let alive = true;
    const load = () => api<Quotes>("/api/site/quotes").then((d) => alive && setQ(d)).catch(() => {});
    load();
    const t = setInterval(load, 10_000);
    return () => {
      alive = false;
      clearInterval(t);
    };
  }, []);
  if (!q || q.quotes.length === 0) return <div className="h-9 border-b border-white/5 bg-ink-900" aria-hidden />;
  const items = [...q.quotes, ...q.quotes];
  return (
    <div className="relative flex h-9 items-center overflow-hidden border-b border-white/5 bg-ink-900 text-xs">
      <div className="z-10 flex h-full shrink-0 items-center gap-2 border-r border-white/5 bg-ink-900 px-3 font-semibold text-muted">
        <span className="size-1.5 rounded-full bg-up-400 animate-pulse-dot" aria-hidden />
        <span className="num">{q.synthetic ? "PRIX SIMULÉS" : "MARCHÉS"}</span>
      </div>
      <div className="relative min-w-0 flex-1 overflow-hidden [mask-image:linear-gradient(90deg,transparent,#000_4%,#000_96%,transparent)]">
        <div className="flex w-max animate-ticker gap-8 pl-6 hover:[animation-play-state:paused]">
          {items.map((x, i) => {
            const up = (x.change_pct ?? 0) >= 0;
            return (
              <span key={`${x.symbol}-${i}`} className="num inline-flex items-center gap-2 whitespace-nowrap" aria-hidden={i >= q.quotes.length}>
                <span className="font-semibold text-fg">{x.symbol}</span>
                <span className="text-muted">{price(x.price, x.digits)}</span>
                <span className={`inline-flex items-center gap-0.5 ${up ? "text-up-400" : "text-down-400"}`}>
                  {up ? <TrendingUp className="size-3" /> : <TrendingDown className="size-3" />}
                  {pct(x.change_pct)}
                </span>
              </span>
            );
          })}
        </div>
      </div>
    </div>
  );
}

export function Nav() {
  const path = usePathname();
  const { me } = useSession();
  const [open, setOpen] = useState(false);
  const [scrolled, setScrolled] = useState(false);
  useEffect(() => setOpen(false), [path]);
  useEffect(() => {
    const on = () => setScrolled(window.scrollY > 8);
    on();
    window.addEventListener("scroll", on, { passive: true });
    return () => window.removeEventListener("scroll", on);
  }, []);
  useEffect(() => {
    document.body.style.overflow = open ? "hidden" : "";
  }, [open]);

  return (
    <>
    <header className={`sticky top-0 z-50 transition-colors duration-300 ${scrolled || open ? "border-b border-white/5 bg-ink-950/85 backdrop-blur-xl" : "bg-transparent"}`}>
      <nav className="container-x flex h-16 items-center justify-between gap-4" aria-label="Navigation principale">
        <Link href="/" className="shrink-0" aria-label="Liberté Financière, accueil">
          <Lockup />
        </Link>
        <div className="hidden items-center gap-1 md:flex">
          {LINKS.map((l) => {
            const active = path?.startsWith(l.href);
            return (
              <Link key={l.href} href={l.href} className={`relative rounded-lg px-3 py-2 text-sm font-medium transition-colors ${active ? "text-white" : "text-muted hover:text-white"}`}>
                {active && <motion.span layoutId="nav-pill" className="absolute inset-0 -z-10 rounded-lg bg-white/[0.06]" transition={{ type: "spring", stiffness: 380, damping: 32 }} />}
                {l.label}
              </Link>
            );
          })}
        </div>
        <div className="hidden items-center gap-2 md:flex">
          {me ? (
            <Link href="/compte/" className="btn btn-ghost btn-sm">
              <User className="size-4" /> {me.name.split(" ")[0]}
              <span className="chip chip-blue !px-2 !py-0 text-[10px]">{me.offer_label}</span>
            </Link>
          ) : (
            <>
              <Link href="/compte/?vue=connexion" className="btn btn-ghost btn-sm">Connexion</Link>
              <Link href="/compte/?vue=inscription" className="btn btn-primary btn-sm">Commencer gratuitement</Link>
            </>
          )}
        </div>
        <button className="btn btn-ghost btn-sm md:hidden" onClick={() => setOpen((o) => !o)} aria-expanded={open} aria-controls="menu-mobile" aria-label={open ? "Fermer le menu" : "Ouvrir le menu"}>
          {open ? <X className="size-5" /> : <Menu className="size-5" />}
        </button>
      </nav>
    </header>
      {/* Outside the header: its backdrop-filter would otherwise become the containing block of this fixed panel. */}
      <AnimatePresence>
        {open && (
          <motion.div
            id="menu-mobile"
            className="fixed inset-0 z-40 overflow-y-auto bg-ink-950/97 pt-24 backdrop-blur-xl md:hidden"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
          >
            <div className="container-x flex flex-col gap-1 py-6">
              {LINKS.map((l, i) => (
                <motion.div key={l.href} initial={{ opacity: 0, x: -12 }} animate={{ opacity: 1, x: 0 }} transition={{ delay: 0.04 * i }}>
                  <Link href={l.href} className="flex items-center justify-between rounded-xl px-3 py-4 text-lg font-semibold hover:bg-white/5">
                    {l.label} <ArrowUpRight className="size-5 text-faint" />
                  </Link>
                </motion.div>
              ))}
              <div className="mt-4 grid gap-2">
                {me ? (
                  <Link href="/compte/" className="btn btn-primary">Mon espace ({me.offer_label})</Link>
                ) : (
                  <>
                    <Link href="/compte/?vue=inscription" className="btn btn-primary">Commencer gratuitement</Link>
                    <Link href="/compte/?vue=connexion" className="btn btn-ghost">Connexion</Link>
                  </>
                )}
              </div>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </>
  );
}

export function Footer() {
  const { site } = useSession();
  const year = new Date().getFullYear();
  return (
    <footer className="mt-24 border-t border-white/5 bg-ink-900/60">
      <div className="container-x grid gap-10 py-14 md:grid-cols-[1.4fr_1fr_1fr_1fr]">
        <div>
          <div className="flex items-center gap-3">
            <Emblem size={52} />
            <Wordmark className="text-xl" />
          </div>
          <p className="mt-4 max-w-sm text-sm leading-relaxed text-muted">{site?.brand.pitch ?? "Robots de trading, formation et copytrading encadré."}</p>
          <div className="mt-5 inline-flex items-center gap-3 rounded-xl border border-white/10 bg-white/[0.02] px-3 py-2">
            <VFMark size={26} />
            <span className="text-xs leading-tight text-muted">
              Cofondé par <span className="text-fg">Khalifa Diop</span>
              <br />& <span className="text-fg">Victor Faye</span>
            </span>
          </div>
        </div>
        <FooterCol title="Plateforme" links={[["Robots", "/robots/"], ["Copytrading", "/copytrading/"], ["Académie", "/academie/"], ["Offres et paiement Wave", "/tarifs/"]]} />
        <FooterCol title="Compte" links={[["Espace membre", "/compte/"], ["Créer un compte", "/compte/?vue=inscription"], ["Console de trading", "/console"]]} />
        <FooterCol title="Informations" links={[["Avertissement sur les risques", "/risques/"], ["Conditions d'utilisation", "/risques/#conditions"], ["Confidentialité", "/risques/#confidentialite"]]} />
      </div>
      <div className="border-t border-white/5">
        <div className="container-x flex flex-col gap-3 py-6 text-xs leading-relaxed text-faint md:flex-row md:items-center md:justify-between">
          <p className="max-w-3xl">
            Le trading sur marge (CFD, forex, indices, or, cryptomonnaies) comporte un risque élevé de perte en capital. Les performances passées, simulées ou
            backtestées ne préjugent pas des performances futures. Aucun contenu de ce site n&apos;est un conseil en investissement personnalisé.
          </p>
          <p className="num shrink-0">© {year} Liberté Financière{site ? ` · v${site.version}` : ""}</p>
        </div>
      </div>
    </footer>
  );
}

function FooterCol({ title, links }: { title: string; links: [string, string][] }) {
  return (
    <div>
      <div className="text-xs font-semibold uppercase tracking-wider text-faint">{title}</div>
      <ul className="mt-4 grid gap-2.5 text-sm">
        {links.map(([label, href]) => (
          <li key={href}>
            {href.startsWith("/console") ? (
              <a href={href} className="text-muted transition-colors hover:text-white">{label}</a>
            ) : (
              <Link href={href} className="text-muted transition-colors hover:text-white">{label}</Link>
            )}
          </li>
        ))}
      </ul>
    </div>
  );
}
