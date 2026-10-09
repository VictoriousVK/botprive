# Coach (graphe G3)

**But.** Relire le journal du membre sur 7, 30 ou 90 jours. Il nomme au plus quatre écarts au plan
mesurés, propose au plus deux leçons concrètes et pose au plus trois questions de réflexion.

**Hors périmètre.** Il ne donne pas de conseil de trade, ne pose aucun diagnostic psychologique ni
aucune étiquette sur la personne, et ne fait aucune prévision de résultat.

- **Entrées.** Statistiques (`perf.kpis`, avec intervalles de Wilson et bootstrap) et comportements
  détectés (`perf.behavior_flags` : surtrading, revanche, lot augmenté après une perte, hors plan,
  hors killzone, près d'une annonce, risque au-delà du plan). Aussi : plan de trading, leçons actives,
  dernier résumé hebdomadaire, question facultative du membre.
- **Sortie.** `CoachVerdict` (`hedgefund/saas/schemas.py`).
  - Le label est parmi `ON_PLAN`, `MINOR_DRIFT`, `MAJOR_DRIFT`, `INSUFFICIENT_DATA` ; il est proposé
    par les règles. Le modèle ne peut que le rendre plus sévère, et seules les règles décident si
    les données suffisent.
  - La confiance est calculée (taille d'échantillon, couverture des R).
  - Chaque leçon suit le gabarit « LEÇON : Quand <situation>, je <action> ».
- **Modèle.** `coach` (Sonnet 5), prompt `hedgefund/saas/prompts/coach.md`. Budget : 3 appels,
  40 000 jetons en entrée, 90 s.
- **Humain dans la boucle.** Le graphe s'interrompt après la proposition. Rien n'est mémorisé avant
  que le membre accepte, reformule ou refuse chaque leçon. Cinq leçons actives au plus ; leur force
  décroît si elles ne sont pas renforcées. Le résumé hebdomadaire est modifiable et supprimable.
- **Vérifications.** Ancrage des chiffres sur les preuves, garde-fou de sortie, texte des leçons
  modifiées revérifié.
- **Tests.** `tests/test_saas_coach.py` : revue par règles, décisions, mémoire, ancrage, injection,
  quotas, isolation. La scorecard couvre le reste.
- **Limites connues.**
  - Sous 20 trades clôturés, le verdict reste prudent (échantillon insuffisant).
  - Le R n'est exact que si le stop initial est connu ; sinon il est estimé depuis le risque du plan
    et marqué comme tel.
