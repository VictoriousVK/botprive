# Analyste de setup ICT (graphe G1)

**But.** Évaluer un symbole à l'instant présent selon les règles ICT de Victor, dimensionner une
position éventuelle avec le risk gate, et présenter une carte de décision au membre.

**Hors périmètre.** Il ne passe aucun ordre, n'émet aucun signal à copier et ne promet aucun résultat.
Le label « Valide selon les règles » décrit la conformité aux règles, pas une probabilité de gain.

- **Moteur.** `engines/ict.py` (définitions versionnées `victor-v0`, bougies **clôturées**
  uniquement). Il détecte swings, FVG avec leur état, liquidité (prise ou non), structure (BOS,
  CHoCH, MSS), contexte horaire (killzones, macros, Silver Bullet) et candidats de setup, avec un
  score de règles et les raisons de rejet.
- **Risk gate.** `engines/risk.py` : taille maximale, risque en devise et en %, limites du plan ou du
  profil de prop firm, annonces proches. Un `BLOCK` est un veto.
- **Graphe.** [ICT ‖ statistiques du membre ‖ briefing] → synthèse → risk gate → débat (optionnel,
  désactivé par défaut) → carte → **interruption** (décision du membre, carte valable 2 h) → audit.
- **Sortie.** `SetupAnalysis` : label, candidat (entrée, invalidation, objectifs, R), contexte ICT,
  risk gate, statistiques du membre sur ce modèle, alignement avec le plan, points à vérifier.
- **Modèle.** `analyste` (Sonnet 5). Débat : `debate` (Sonnet 5) et `judge` (Opus 5), qui ne peuvent
  que maintenir ou rétrograder l'avis. Prompt `prompts/analyste.md`. Budget : 5 appels, 60 000 jetons
  en entrée, 90 s.
- **Tests.** `tests/test_saas_risk.py`, `tests/test_saas_engines.py` (golden set synthétique,
  précision et rappel), `tests/test_saas_p2.py` (débat). La scorecard vérifie aussi l'absence
  d'anticipation (aucune bougie non clôturée).
- **Limites connues.**
  - Sur un serveur sans MT5, les prix sont simulés et chaque carte le signale.
  - La valeur du point est lue chez le broker de la plateforme et peut différer chez celui du membre.
  - Les profils de prop firm restent à vérifier sur leur règlement officiel.
  - Le golden set réel reste à annoter.
