// Programme officiel « Victorious Trader », formation ICT de Victor Faye (source : affiche du programme).

export type Module = { n: number; title: string; subtitle?: string; points: string[] };

export const MODULES: Module[] = [
  { n: 1, title: "Introduction & Vision ICT", points: ["Présentation de la méthodologie ICT (Inner Circle Trader)", "Objectif : devenir un trader discipliné et précis", "Comprendre la structure du marché algorithmique", "Bases mentales et techniques"] },
  { n: 2, title: "L'IPDA Cycle", subtitle: "Institutional Price Delivery Algorithm", points: ["IPDA Levels : High – RB – OB – FVG – OB – LV – BB – MB", "Lecture du cycle complet et repérage sur le graphique", "Application pratique (NAS100, XAUUSD, EURUSD)"] },
  { n: 3, title: "AMD Cycle", subtitle: "Accumulation – Manipulation – Distribution", points: ["Structure interne du cycle AMD", "Corrélation entre IPDA et AMD", "Exercices : identifier un AMDX complet sur un graphique"] },
  { n: 4, title: "Le 90-Minute Cycle", points: ["Cycles 00h–1h30, 1h30–3h, etc.", "Premier FVG de minuit", "Premier mouvement de liquidité (Midnight Model)"] },
  { n: 5, title: "L'OPR de Londres", subtitle: "Opening Price Range", points: ["Manipulation de Londres", "Étude du Macro + premier FVG (Midnight)", "Gestion du risque pendant la session de Londres"] },
  { n: 6, title: "Silver Bullet Concept", points: ["Liquidité + FVG + BIAS entre 13h et 14h30 (PM Session)", "Mise en pratique sur données réelles"] },
  { n: 7, title: "MMXM", subtitle: "Market Maker Models", points: ["MMBM (Buy Model) et MMSM (Sell Model)", "Exemples pratiques et repérage sur différentes sessions"] },
  { n: 8, title: "ICT Classic Buy Day", points: ["Détermination du BIAS et de la narrative du jour", "Plan de trading : session → manipulation → expansion"] },
  { n: 9, title: "SMT + MACRO", subtitle: "Entrée Venom – ICT Mentorship 2022", points: ["Divergences SMT (NAS100 / ES / DXY)", "Étude du modèle Venom Entry (ICT 2022)"] },
  { n: 10, title: "Breakaway Gaps & First FVG", subtitle: "PM 90min Cycle", points: ["First FVG et Breakaway Gap", "Lecture du premier breaker (pré-marché, 6h00 GMT)"] },
  { n: 11, title: "ICT Mentorship 2024", subtitle: "NWOG / NDOG", points: ["New Week Opening Gap (NWOG)", "New Day Opening Gap (NDOG)", "Application sur les indices US"] },
  { n: 12, title: "One Setup For Life", points: ["Identification du contexte parfait", "Gestion du risque, des entrées et des sorties", "Backtesting complet du modèle"] },
  { n: 13, title: "Shadow Model", subtitle: "7h–9h / OPR 7h–7h30", points: ["Lecture du Shadow Model", "Stratégie sur la plage horaire pré-Londres"] },
  { n: 14, title: "Open 8h30 : news ou pas", points: ["Lecture des journées avec ou sans news", "Stratégie de confirmation sur la session US"] },
  { n: 15, title: "RTH Gap & London Close Macro", points: ["Lecture du RTH Gap (Regular Trading Hours)", "Interprétation du London Close Macro pour préparer le lendemain"] },
  { n: 16, title: "TGIF", subtitle: "Friday Model", points: ["Lecture du Friday Macro Range", "Optimisation des setups de fin de semaine", "Récapitulatif de la semaine et planification de la suivante"] },
];

export const PILLARS = [
  { title: "Une méthodologie complète et pratique", icon: "target" },
  { title: "Des cas réels sur NAS100, XAUUSD, EURUSD", icon: "chart" },
  { title: "Un accompagnement personnalisé", icon: "brain" },
  { title: "Accès à vie à un groupe de traders d'élite", icon: "infinity" },
] as const;

export const BONUSES = ["Méthode ICT complète", "Compréhension profonde du marché", "Accès aux contenus exclusifs", "Échanges directs avec Victor Faye", "Accès à vie au groupe d'élite"];

export const QUOTES = ["Maîtrise les marchés, construis ta liberté.", "Investis sur toi, c'est le meilleur trade !"];
