// Captures of the real product for the films.
//
// Starts the platform in demonstration mode (python -m hedgefund.web demo: fictitious accounts and
// trades, simulated prices, a banner on every page), walks through the screens the films show,
// and writes public/captures/*.jpg with public/captures/manifest.json: for each screen its size and
// the position of the elements the films point at (sections, buttons, fields). The films only ever
// show these captures: nothing in them is redrawn by hand.
//
//   npm run capture                      (from apps/motion; Python and the project installed)
//   PYTHON=..\..\.venv\Scripts\python.exe npm run capture      (Windows, project venv)
//   CAPTURE_CHROMIUM=/path/to/chrome npm run capture           (a Chromium already on the machine)

import { spawn } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const HERE = dirname(fileURLToPath(import.meta.url));
const MOTION = resolve(HERE, "..");
const REPO = resolve(MOTION, "../..");
const OUT = join(MOTION, "public/captures");
const DATA = join(MOTION, ".cache/demo");
const PORT = Number(process.env.CAPTURE_PORT ?? 8790);
const BASE = `http://127.0.0.1:${PORT}`;
const PYTHON = process.env.PYTHON ?? (existsSync(join(REPO, ".venv/Scripts/python.exe")) ? join(REPO, ".venv/Scripts/python.exe") : existsSync(join(REPO, ".venv/bin/python")) ? join(REPO, ".venv/bin/python") : "python");
const DESKTOP = { width: 1440, height: 900, scale: 2 };
const PHONE = { width: 390, height: 844, scale: 3 };

const manifest = { generated_at: new Date().toISOString(), base: "demo", desktop: DESKTOP, phone: PHONE, shots: {} };
const errors = [];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------------------------------------------------------------- server
async function startServer() {
  mkdirSync(join(MOTION, ".cache"), { recursive: true });
  const args = ["-m", "hedgefund.web", "--data-dir", DATA, "demo", "--port", String(PORT)];
  if (existsSync(join(DATA, "demo.json"))) args.push("--reset");
  const proc = spawn(PYTHON, args, { cwd: REPO, stdio: ["ignore", "pipe", "pipe"] });
  let log = "";
  proc.stdout.on("data", (d) => (log += d));
  proc.stderr.on("data", (d) => (log += d));
  for (let i = 0; i < 90; i++) {
    try {
      const r = await fetch(`${BASE}/api/site`);
      if (r.ok && (await r.json()).demo) return proc;
    } catch {
      /* not up yet */
    }
    if (proc.exitCode !== null) break;
    await sleep(1000);
  }
  proc.kill();
  throw new Error(`le serveur de démonstration ne répond pas :\n${log.slice(-2000)}`);
}

// ---------------------------------------------------------------- helpers
async function boxOf(page, loc) {
  const l = typeof loc === "function" ? loc(page) : loc;
  try {
    await l.first().waitFor({ state: "visible", timeout: 4000 });
    const b = await l.first().boundingBox();
    const sy = await page.evaluate(() => window.scrollY);
    return b ? { x: Math.round(b.x), y: Math.round(b.y + sy), w: Math.round(b.width), h: Math.round(b.height) } : null;
  } catch {
    return null;
  }
}

/** Saves a capture and the boxes of the elements the films point at (page coordinates, CSS px). */
async function shot(page, name, { full = false, targets = {}, device = DESKTOP } = {}) {
  await page.evaluate(() => window.scrollTo(0, 0));
  await sleep(450);
  const boxes = {};
  for (const [k, loc] of Object.entries(targets)) {
    const b = await boxOf(page, loc);
    if (b) boxes[k] = b;
    else errors.push(`${name} : élément « ${k} » introuvable`);
  }
  await page.evaluate(() => window.scrollTo(0, 0));
  const file = `${name}.jpg`;
  await page.screenshot({ path: join(OUT, file), fullPage: full, type: "jpeg", quality: 90 });
  const size = await page.evaluate(() => ({ w: document.documentElement.clientWidth, h: document.documentElement.scrollHeight }));
  manifest.shots[name] = { file, width: size.w, height: full ? size.h : device.height, scale: device.scale, full, url: new URL(page.url()).pathname + new URL(page.url()).search, boxes };
  console.log(`  ${name}${Object.keys(boxes).length ? ` (${Object.keys(boxes).length} zones)` : ""}`);
}

const section = (title) => (p) => p.locator("section").filter({ has: p.getByRole("heading", { name: title }) });
const text = (t, exact = false) => (p) => p.getByText(t, { exact });
const button = (name, exact = false) => (p) => p.getByRole("button", { name, exact });
const link = (name, exact = false) => (p) => p.getByRole("link", { name, exact });
/** The nearest enclosing block of an element: a card, a fieldset, a form row. */
const around = (loc, xpath = "div[contains(@class,'rounded-xl') or contains(@class,'card')]") => (p) => loc(p).locator(`xpath=ancestor::${xpath}[1]`);
const last = (loc) => (p) => loc(p).last();

async function go(page, path, wait = 900) {
  await page.goto(BASE + path, { waitUntil: "domcontentloaded" });
  await page.waitForLoadState("networkidle", { timeout: 15000 }).catch(() => {});
  await sleep(wait);
}

async function newContext(browser, device, creds) {
  const ctx = await browser.newContext({ viewport: { width: device.width, height: device.height }, deviceScaleFactor: device.scale, reducedMotion: "reduce",
    isMobile: device === PHONE, hasTouch: device === PHONE, locale: "fr-FR", timezoneId: "Africa/Dakar" });
  if (creds?.email) await ctx.request.post(`${BASE}/api/m/login`, { data: { email: creds.email, password: creds.password } });
  if (creds?.username) await ctx.request.post(`${BASE}/api/auth/login`, { data: { username: creds.username, password: creds.password } });
  const page = await ctx.newPage();
  page.on("pageerror", (e) => errors.push(`erreur de page : ${e.message}`));
  return { ctx, page };
}

// ---------------------------------------------------------------- the walk
async function publicPages(browser) {
  console.log("Site public");
  const { ctx, page } = await newContext(browser, DESKTOP);
  await go(page, "/");
  await shot(page, "home", { targets: { start: link("Commencer gratuitement"), nav: (p) => p.locator("header nav").first(), banner: text("Démonstration : comptes, trades") } });
  await shot(page, "home_full", { full: true });
  await go(page, "/tarifs/");
  await shot(page, "tarifs", { full: true, targets: { offers: (p) => p.getByText("Starter", { exact: true }).first().locator("xpath=ancestor::div[contains(@class,'grid')][1]"),
    methods: (p) => p.getByText("Wave", { exact: true }).first().locator("xpath=ancestor::div[1]") } });
  await go(page, "/formation-ict/");
  await shot(page, "formation_ict");
  await go(page, "/academie/");
  await shot(page, "academie", { full: true, targets: { course: text("Les FVG en pratique") } });
  await go(page, "/robots/");
  await shot(page, "robots", { full: true });
  await go(page, "/copytrading/");
  await shot(page, "copytrading");
  await ctx.close();
}

async function signUpAndOnboarding(browser) {
  console.log("Inscription et mise en route");
  const { ctx, page } = await newContext(browser, DESKTOP);
  await go(page, "/compte/?vue=inscription", 1200);
  const T = { name: (p) => p.getByLabel("Nom complet"), email: (p) => p.getByLabel("E-mail"), next: button("Continuer"), dial: (p) => p.getByRole("img", { name: /Heure de New York/ }), tabs: (p) => p.getByRole("tablist") };
  await shot(page, "auth_register_1", { targets: T });
  await page.getByLabel("Nom complet").fill("Karim Sow");
  await page.getByLabel("E-mail").fill("karim.demo@example.com");
  await sleep(300);
  await shot(page, "auth_register_1_filled", { targets: T });
  await page.getByRole("button", { name: "Continuer" }).click();
  await sleep(600);
  await page.getByLabel("Mot de passe", { exact: true }).fill("Bougies-et-Liquidite-2026");
  await page.getByRole("checkbox").check();
  await sleep(400);
  await shot(page, "auth_register_2", { targets: { password: (p) => p.getByLabel("Mot de passe", { exact: true }), meter: around(text("Excellent"), "div[contains(@class,'field')]"),
    terms: around((p) => p.getByRole("checkbox"), "label"), submit: button("Créer mon compte"), form: around(text("Sécuriser votre compte"), "div[contains(@class,'card')]") } });
  await page.getByRole("button", { name: "Créer mon compte" }).click();
  await page.waitForURL("**/app/bienvenue/", { timeout: 15000 });
  await sleep(1200);
  const onb = { rail: text("Prop firm", true), next: button("Continuer"), skip: button("Passer", true) };
  await shot(page, "onb_1", { full: true, targets: { ...onb, level: button("Intermédiaire"), levels: around(button("Intermédiaire"), "fieldset"), markets: around(text("Vos marchés"), "fieldset") } });
  await page.getByRole("button", { name: "Intermédiaire" }).click();
  await page.getByRole("button", { name: "1 à 3 ans" }).click();
  await page.getByRole("button", { name: "MNQ", exact: true }).click();
  await page.getByRole("button", { name: "Réussir une évaluation prop firm" }).click();
  await sleep(300);
  await shot(page, "onb_1_filled", { full: true, targets: { ...onb, level: button("Intermédiaire"), levels: around(button("Intermédiaire"), "fieldset"), markets: around(text("Vos marchés"), "fieldset"),
    mnq: (p) => p.getByRole("button", { name: "MNQ", exact: true }) } });
  await page.getByRole("button", { name: "Continuer" }).click();
  await page.getByText("Tradez-vous pour une prop firm").waitFor();
  await sleep(500);
  await page.getByRole("button", { name: "Topstep Futures" }).click();
  await page.getByRole("button", { name: "50K", exact: true }).click();
  await sleep(700);
  await shot(page, "onb_2", { full: true, targets: { ...onb, firm: button("Topstep Futures"), firms: (p) => p.getByRole("button", { name: "Topstep Futures" }).locator("xpath=.."),
    size: button("50K", true), rules: around(text("Règles suivies")) } });
  await page.getByRole("button", { name: "Continuer" }).click();
  await page.getByText("Votre plan de risque").waitFor();
  await sleep(600);
  await shot(page, "onb_3", { full: true, targets: { ...onb, sliders: (p) => p.getByText("Risque par trade").locator("xpath=ancestor::div[contains(@class,'grid')][1]"),
    summary: around(text("Je risque au plus")), killzones: around(text("Vos killzones"), "fieldset"), warning: text(/dépasse celle de la firme/) } });
  await page.getByRole("button", { name: "Continuer" }).click();
  await page.getByText("Votre premier compte").waitFor();
  await sleep(500);
  await shot(page, "onb_4", { targets: { rail: onb.rail, label: (p) => p.getByLabel("Nom du compte"), fields: (p) => p.getByLabel("Nom du compte").locator("xpath=ancestor::div[contains(@class,'grid')][1]"),
    finish: button("Terminer", true) } });
  await page.getByRole("button", { name: "Terminer", exact: true }).click();
  await page.getByText("Votre espace est prêt").waitFor();
  await sleep(1200);
  await shot(page, "onb_done", { targets: { import: link(/Importer mon historique/), next: (p) => p.getByRole("link", { name: /Importer mon historique/ }).locator("xpath=ancestor::div[contains(@class,'grid')][1]"),
    ready: text("Votre espace est prêt"), dashboard: link("Aller au tableau de bord") } });
  await ctx.close();
}

async function traderSpace(browser, creds) {
  console.log("Espace de trading (Awa, démo)");
  const { ctx, page } = await newContext(browser, DESKTOP, creds.trader);
  await go(page, "/app/", 1500);
  await shot(page, "dashboard", { full: true, targets: {
    tabs: (p) => p.getByRole("link", { name: "Journal", exact: true }).locator(".."), ask: (p) => p.getByPlaceholder(/revois ma semaine/), perf: section("Performance (30 jours)"),
    guard: section("Garde-fou"), behaviours: section("Comportements repérés"), lessons: section("Leçons actives"), killzones: section("Par killzone (30 jours)"),
    analyses: section("Dernières analyses"), plan: text("Quant Elite", true), banner: text("Prix simulés sur cette plateforme") } });
  await go(page, "/app/journal/", 1200);
  await shot(page, "journal", { targets: { table: (p) => p.locator("table").first(), row: (p) => p.locator("tbody tr").first() } });
  await page.locator("tbody tr").first().click();
  await page.getByRole("dialog").getByText("Émotion avant").waitFor({ timeout: 8000 }).catch(() => {});
  await sleep(700);
  await shot(page, "journal_drawer", { targets: { dialog: (p) => p.getByRole("dialog") } });
  await go(page, "/app/journal/?vue=stats", 1500);
  await shot(page, "journal_stats", { full: true, targets: { kpis: section("Indicateurs") } });
  await go(page, "/app/journal/?vue=comptes", 1200);
  await shot(page, "journal_comptes", { full: true, targets: { accounts: text("FTMO 100K (démo)"), import: text(/rapport HTML|Importer/) } });

  await go(page, "/app/revue/", 1200);
  await page.getByRole("button", { name: "30 jours", exact: true }).click();
  await shot(page, "coach_before", { targets: { period: button("30 jours", true), launch: button("Lancer la revue"), question: (p) => p.getByPlaceholder(/pourquoi je perds/) } });
  await page.getByRole("button", { name: "Lancer la revue" }).click();
  await page.getByText("Verdict du Coach").waitFor({ timeout: 40000 });
  await sleep(1200);
  await shot(page, "coach_verdict", { full: true, targets: { run: section("Nouvelle revue"), verdict: section("Verdict du Coach"),
    kpis: (p) => p.locator("section").filter({ has: p.getByRole("heading", { name: "Verdict du Coach" }) }).locator("dl, .grid").first(),
    measures: (p) => p.getByText(/Écarts mesurés/i).locator("xpath=.."), lessons: (p) => p.getByText(/Leçons proposées/i).last().locator("xpath=.."),
    accept: button("Accepter"), memory: section("Mémoire du Coach") } });
  const accept = page.getByRole("button", { name: "Accepter" });
  if (await accept.count()) {
    await accept.first().click();
    await sleep(1200);
    await shot(page, "coach_lesson", { full: true, targets: { lessons: section("Leçons actives") } });
  }

  await go(page, "/app/risque/", 1500);
  await shot(page, "risque_ftmo", { full: true, targets: { limits: section("État des limites"), calc: section("Calculateur de taille"), profiles: section("Profils de prop firm"),
    objectives: around(text("Objectifs de l'évaluation")), account: (p) => p.getByLabel("Compte") } });
  await page.getByLabel("Compte").selectOption({ label: "Topstep 50K (démo)" });
  await sleep(1500);
  await page.getByLabel("Symbole").fill("MNQ");
  await page.getByLabel("Entrée", { exact: true }).fill("20000");
  await page.getByLabel("Stop", { exact: true }).fill("19975");
  await page.getByRole("button", { name: "Calculer" }).click();
  await page.getByText("contrat(s)").first().waitFor({ timeout: 10000 }).catch(() => {});
  await sleep(900);
  await shot(page, "risque_topstep", { full: true, targets: { limits: section("État des limites"), calc: section("Calculateur de taille"), result: text("contrat(s)"),
    resultBlock: (p) => p.getByText("contrat(s)").first().locator("xpath=ancestor::div[contains(@class,'grid') or contains(@class,'rounded')][1]") } });

  await go(page, "/app/analyse/", 1500);
  await shot(page, "analyse_before", { targets: { form: section("Nouvelle analyse"), run: button("Analyser", true) } });
  await page.getByRole("button", { name: "Analyser", exact: true }).click();
  await page.getByText("Données au").first().waitFor({ timeout: 60000 });
  await sleep(2000);
  await shot(page, "analyse_card", { full: true, targets: { chart: (p) => p.getByRole("img", { name: /Graphique/ }), gate: section("Risk gate"), briefing: section("Briefing et calendrier"),
    card: (p) => p.locator("section").filter({ has: p.getByText("Données au") }), tradingview: section("Alertes TradingView") } });

  await go(page, "/app/mentor/", 1200);
  await page.getByPlaceholder("Ex. : quelle différence").fill("Qu'est-ce qu'un fair value gap, et comment le repérer ?");
  await page.getByRole("button", { name: "Demander" }).click();
  await page.getByRole("heading", { name: "Réponse" }).waitFor({ timeout: 20000 });
  await sleep(900);
  await shot(page, "mentor", { full: true, targets: { question: section("Votre question"), answer: section("Réponse"), sources: (p) => p.getByText("Sources", { exact: true }).locator("xpath=.."),
    label: text("Réponse partielle") } });

  await go(page, "/app/formation/", 1200);
  await shot(page, "formation", { full: true });
  await go(page, "/app/labo/", 1200);
  const sim = page.getByRole("button", { name: "Simuler" });
  if (await sim.count()) {
    await sim.click();
    await page.getByText("Drawdown médian").waitFor({ timeout: 15000 }).catch(() => {});
    await sleep(900);
  }
  await shot(page, "labo", { full: true, targets: { mc: section("Monte Carlo"), demo: section("Démo / réel"), robust: section("Robustesse d'une stratégie"), eas: section("Surveillance des EA") } });
  await go(page, "/app/ea/", 1200);
  await shot(page, "ea", { full: true, targets: { spec: section("Spécifications") } });
  await go(page, "/app/reglages/", 1200);
  await shot(page, "reglages", { full: true, targets: { plan: section("Plan de trading"), profile: section("Profil"), mt5: section("Synchronisation MT5"), notif: section("Notifications"),
    api: section("API (lecture seule)"), data: section("Vos données") } });
  await go(page, "/compte/", 1500);
  await shot(page, "compte", { full: true, targets: { plan: around((p) => p.getByText("Mon abonnement").or(p.getByText("Mes accès"))), links: (p) => p.getByRole("link", { name: /Espace de trading/ }).locator("xpath=.."),
    payments: (p) => p.getByText("Mes paiements").locator("xpath=ancestor::section[1]") } });
  await ctx.close();
}

async function prospect(browser, creds) {
  console.log("Membre gratuit (Moussa, démo)");
  const { ctx, page } = await newContext(browser, DESKTOP, creds.prospect);
  await go(page, "/app/analyse/", 1500);
  await shot(page, "free_locked", { targets: { lock: around(text(/Fonction incluse/)) } });
  await ctx.close();
}

async function admin(browser, creds) {
  console.log("Administration et console");
  const { ctx, page } = await newContext(browser, DESKTOP, creds.operator);
  await go(page, "/admin/", 2500);
  await shot(page, "admin_overview", { full: true, targets: { tabs: (p) => p.getByRole("tablist").first() } });
  const tab = async (name) => {
    await page.getByRole("tab", { name }).click();
    await sleep(1400);
  };
  await tab(/Paiements/);
  await shot(page, "admin_payments", { targets: { validate: button("Valider"), row: (p) => p.locator("tbody tr").first() } });
  await page.getByRole("button", { name: "Valider" }).first().click();
  await sleep(600);
  const confirm = page.getByRole("button", { name: /Confirmer|Valider le paiement/ });
  if (await confirm.count()) {
    await confirm.first().click();
    await sleep(900);
  }
  await page.getByRole("button", { name: "Payés" }).click().catch(() => {});
  await sleep(900);
  await shot(page, "admin_payments_paid", { targets: { row: (p) => p.locator("tbody tr").first() } });
  await tab("Membres");
  await shot(page, "admin_members", { targets: { table: (p) => p.locator("table").first() } });
  await tab("Académie");
  await shot(page, "admin_academie");
  await tab("SaaS IA");
  await sleep(1200);
  await shot(page, "admin_saas", { full: true, targets: { health: section(/Santé du SaaS/) } });
  await tab("Réglages");
  await shot(page, "admin_reglages", { full: true, targets: { community: (p) => p.getByRole("heading", { name: "Liens de la communauté privée" }).locator("xpath=ancestor::div[contains(@class,'card')][1]"),
    alerts: (p) => p.getByText(/Alertes de paiement/).first().locator("xpath=ancestor::div[contains(@class,'card')][1]") } });

  await page.goto(`${BASE}/console`, { waitUntil: "domcontentloaded" });
  await sleep(3500);
  await shot(page, "console_dashboard", { targets: { tabs: (p) => p.getByRole("tablist"), equity: text("Valeur du portefeuille"), limits: text("Alertes", true) } });
  await page.getByRole("tab", { name: "Bots" }).click();
  await sleep(1500);
  await shot(page, "console_bots", { full: true, targets: { create: button("+ Nouveau bot"), strategies: text("Stratégies disponibles") } });
  // A bot on gold with the ICT strategy, then a backtest on the simulated history.
  await page.getByRole("button", { name: /Créer un bot avec cette stratégie/ }).first().click();
  await sleep(1200);
  await page.locator("#bot-name").fill("Or ICT (démo)");
  await page.getByRole("searchbox", { name: "Rechercher un actif" }).first().fill("XAU");
  await sleep(1200);
  await page.locator("#pickers .result").filter({ hasText: "XAUUSD" }).first().click().catch(() => errors.push("console : XAUUSD introuvable dans le sélecteur"));
  await sleep(600);
  await shot(page, "console_bot_form", { targets: { dialog: (p) => p.locator("#dlg-bot"), backtest: (p) => p.locator("#bot-backtest") } });
  await page.locator("#bot-backtest").click();
  await page.locator("#dlg-backtest[open]").waitFor({ timeout: 15000 }).catch(() => {});
  await page.waitForFunction(() => {
    const t = document.querySelector("#bt-content")?.textContent ?? "";
    return t.length > 80 && !/Calcul|en cours/i.test(t);
  }, null, { timeout: 120000 }).catch(() => errors.push("console : le backtest n'a pas rendu de résultat"));
  await sleep(1500);
  await shot(page, "console_backtest", { targets: { dialog: (p) => p.locator("#dlg-backtest") } });
  await page.keyboard.press("Escape");
  await page.keyboard.press("Escape");
  await sleep(500);
  await page.getByRole("tab", { name: "Réglages" }).click();
  await sleep(1500);
  const card = (t) => (p) => p.getByRole("heading", { name: t }).locator("xpath=ancestor::*[contains(@class,'card') or self::section][1]");
  await shot(page, "console_settings", { full: true, targets: { mode: card("Mode d'exécution"), real: card("Trading sur compte réel"), limits: card("Limites de risque (moteur déterministe)"),
    security: card("Sécurité du compte") } });
  await ctx.close();
}

async function phone(browser, creds) {
  console.log("Téléphone");
  let { ctx, page } = await newContext(browser, PHONE);
  await go(page, "/");
  await shot(page, "m_home", { device: PHONE });
  await go(page, "/compte/?vue=inscription", 1200);
  await page.getByLabel("Nom complet").fill("Aïssatou Ba");
  await page.getByLabel("E-mail").fill("aissatou.demo@example.com");
  await shot(page, "m_auth", { device: PHONE, targets: { next: button("Continuer") } });
  await ctx.close();
  ({ ctx, page } = await newContext(browser, PHONE, creds.trader));
  await go(page, "/app/", 1500);
  await shot(page, "m_dashboard", { device: PHONE, full: true, targets: { perf: section("Performance (30 jours)"), behaviours: section("Comportements repérés"), guard: section("Garde-fou") } });
  await go(page, "/app/revue/", 1200);
  await page.getByRole("button", { name: "30 jours", exact: true }).click();
  await page.getByRole("button", { name: "Lancer la revue" }).click();
  await page.getByText("Verdict du Coach").waitFor({ timeout: 40000 });
  await sleep(1200);
  await shot(page, "m_coach", { device: PHONE, full: true, targets: { verdict: section("Verdict du Coach") } });
  await go(page, "/app/risque/", 1500);
  await shot(page, "m_risque", { device: PHONE, full: true, targets: { limits: section("État des limites") } });
  await go(page, "/app/bienvenue/", 1200);
  await page.getByRole("button", { name: "Continuer" }).click();
  await page.getByText("Tradez-vous pour une prop firm").waitFor();
  await page.getByRole("button", { name: "FTMO CFD et Forex" }).click();
  await sleep(800);
  await shot(page, "m_onb_firm", { device: PHONE, full: true, targets: { rules: text("Règles suivies") } });
  await ctx.close();
}

// ---------------------------------------------------------------- main
// npm run capture -- console phone   re-captures only these sections and keeps the others.
const SECTIONS = { public: publicPages, signup: signUpAndOnboarding, trader: traderSpace, prospect, admin, phone };
const only = process.argv.slice(2).filter((a) => a in SECTIONS);
if (only.length && existsSync(join(OUT, "manifest.json"))) manifest.shots = JSON.parse(readFileSync(join(OUT, "manifest.json"), "utf8")).shots;
mkdirSync(OUT, { recursive: true });
console.log(`Démonstration : ${PYTHON} -m hedgefund.web demo (données dans ${DATA})`);
const server = await startServer();
try {
  const creds = JSON.parse(readFileSync(join(DATA, "demo.json"), "utf8"));
  const browser = await chromium.launch(process.env.CAPTURE_CHROMIUM ? { executablePath: process.env.CAPTURE_CHROMIUM } : {});
  try {
    for (const [name, run] of Object.entries(SECTIONS)) if (!only.length || only.includes(name)) await run(browser, creds);
  } finally {
    await browser.close();
  }
  writeFileSync(join(OUT, "manifest.json"), JSON.stringify(manifest, null, 1));
  console.log(`\n${Object.keys(manifest.shots).length} captures dans public/captures`);
  if (errors.length) console.log(`À vérifier :\n- ${errors.join("\n- ")}`);
} finally {
  server.kill();
}
