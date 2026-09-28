# Fiches des agents (model cards)

Une fiche par agent du SaaS : ce qu'il fait, ce qu'il ne fait pas, d'où viennent ses chiffres, ce qui
le vérifie. Toute modification d'un agent (prompt, modèle, outils, schéma) met à jour sa fiche et le
manifeste de version **avant** le merge (`python -m hedgefund.saas manifest`).

| Agent | Graphe | Modèle (clé logique) | Fiche |
|---|---|---|---|
| Coach | G3 | `coach` | [coach.md](coach.md) |
| Analyste de setup ICT | G1 | `analyste` (+ `debate`, `judge`) | [analyste.md](analyste.md) |
| Mentor | — | `mentor` | [mentor.md](mentor.md) |
| Research (briefing) | G4 | `research` | [research.md](research.md) |
| Routeur | — | `router` | [router.md](router.md) |
| Usine EA | G2 | `ea_factory` | [ea_factory.md](ea_factory.md) |

Règles communes :

- **Chiffres.** Ils viennent des moteurs déterministes (`hedgefund/saas/engines/`), transmis comme
  preuves. Le modèle écrit des mots et fait des choix dans des listes fermées. `ungrounded_numbers`
  bloque tout nombre absent des preuves.
- **Sans modèle.** Sans modèle disponible (pas de clé, budget épuisé, refus, sortie invalide), l'agent
  rend sa sortie déterministe avec l'avertissement « narration IA indisponible ».
- **Garde-fous.** Ils s'appliquent en entrée (injection, demande de conseil, données personnelles) et
  en sortie (promesse de gain, instruction d'ordre, étiquette psychologique).
- **Aucune action externe.** Aucun agent ne passe d'ordre ni n'écrit chez un tiers. Les décisions
  (leçons, carte de setup, EA en démo) sont prises par le membre et tracées dans l'audit.
- **Évaluation.** `python -m pytest -q` et `python -m hedgefund.saas eval` (scorecard, équipe rouge
  `evals/redteam.yaml`).
