# Usine EA (graphe G2)

**But.** Transformer une spécification validée par le membre en Expert Advisor MQL5 revu et compilé,
prêt pour un **compte démo**.

**Hors périmètre.** Aucun déploiement en réel, aucune performance revendiquée, ni martingale, ni
grille, ni DLL, ni appel réseau.

- **Boucle.** Génération → revue déterministe → compilation MetaEditor → évaluation. La boucle compte
  6 tours au plus et s'arrête si les mêmes erreurs reviennent. Les erreurs de revue et de compilation
  sont renvoyées au générateur.
- **Revue déterministe** (`CHECKS` dans `ea_factory.py`) :
  - numéro magique 770077 en paramètre ;
  - résultat de chaque ordre vérifié ;
  - lot normalisé ; taille calculée depuis le risque ;
  - distance minimale du stop ;
  - décisions à la clôture d'une bougie ;
  - heure de New York depuis `TimeGMT` ;
  - filtre de spread ; cycle de vie `OnInit` et `OnDeinit`.
- **Sortie.** Verdict `READY_FOR_DEMO`, `REVIEWED_NOT_COMPILED` ou `NEEDS_WORK`, avec le code, les
  hypothèses et une model card de l'EA (statut « compilé, non testé », protocole de backtest
  restant à suivre).
- **Humain dans la boucle.** L'essai en démo exige l'approbation explicite du membre, tracée dans
  l'audit.
- **Modèle.** `ea_factory` (Opus 5, effort élevé), prompt `prompts/ea_factory.md`. Budget : 6 appels,
  45 minutes. Offre Quant Elite, 4 générations par mois.
- **Tests.** `tests/test_saas_p2.py` : revue, lecture du journal de MetaEditor, boucle corrigée puis
  compilée, arrêt sur non-progrès, droits.
- **Limites connues.** La compilation réelle demande le service Windows (`compile-server`) ; sans
  lui, la compilation est « non vérifiée ». Un EA compilé n'est pas un EA testé : backtest,
  walk-forward et démo suivie restent à faire (`.claude/skills/backtest-protocol`).
