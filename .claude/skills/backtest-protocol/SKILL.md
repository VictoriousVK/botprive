---
name: backtest-protocol
description: Protocole anti-sur-ajustement pour valider une stratégie ou un EA (walk-forward, holdout, coûts, Monte Carlo, DSR, anti-look-ahead, période après le cutoff des modèles). À suivre avant toute conclusion sur une performance.
---

# Protocole de backtest

1. **Spécification versionnée** avant le premier test (`strategy_specs`) : règles, marchés, sessions,
   gestion du risque. Toute modification crée une nouvelle version, et chaque essai est compté.
2. **Découpage** : développement (fenêtres de walk-forward) puis **holdout** final, jamais regardé pendant
   le développement ; il ne s'exécute qu'une fois, sur décision humaine.
3. **Walk-forward** : fenêtres roulantes ou expansives ; paramètres choisis sur l'entraînement, mesurés
   sur la fenêtre suivante seulement.
4. **Coûts réels** : spread moyen et maximal du broker, commission, slippage (au moins 1 point sur l'or,
   plus aux annonces), swap.
5. **Robustesse** : Monte Carlo sur l'ordre des trades (drawdown au 95ᵉ centile), sensibilité des
   paramètres (±20 %), plusieurs régimes de marché.
6. **Tests multiples** : Sharpe dégonflé (DSR) avec le nombre réel d'essais ; DSR ≥ 0,50 pour passer.
7. **Anti-look-ahead** : relancer avec les données décalées ; un résultat qui change révèle une fuite.
8. **Si un LLM décide** : période de test **postérieure** au cutoff d'entraînement de chaque modèle.
9. **Démo puis réel** : 3 mois minimum de réel suivi par un vérificateur indépendant avant toute vente ;
   rapport démo/réel (spread, slippage, heures d'exécution, rejets).
10. **Communication** : aucun chiffre de performance publié sans track record réel, daté, avec les pertes.
