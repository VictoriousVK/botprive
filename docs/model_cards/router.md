# Routeur

**But.** Orienter le message libre du tableau de bord vers le bon service : revue du journal, analyse
de setup, question de cours, risque, briefing, usine EA ou compte.

- **Règles d'abord.** Des expressions reconnues suffisent dans la plupart des cas, sans modèle.
- **Modèle ensuite.** `router` (Haiku 4.5, 1 appel, 10 s) ; sous 60 % de confiance, un menu est
  proposé au lieu de deviner.
- **Demande de conseil.** « J'achète ? », « donne-moi un signal »… reçoit la réponse fixe de refus,
  avec l'avertissement.
- **Tests.** `tests/test_saas_coach.py` (routeur) et la ligne « routeur » de la scorecard, sur les cas
  de `evals/redteam.yaml`.
