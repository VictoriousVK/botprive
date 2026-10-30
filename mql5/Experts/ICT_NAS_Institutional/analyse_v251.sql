-- ICT NAS Institutional v2.51 : requêtes d'analyse de Common\Files\ICTNAS\ict_nas.sqlite
-- (DB Browser for SQLite, onglet « Exécuter le SQL », ou Python : sqlite3)
-- Copie la base après chaque backtest : elle est vidée au test suivant (InpFreshDBInTester).

-- 1. Quels couples modèle x session ont une espérance positive ?
--    Lance d'abord un backtest long avec InpProfile = Agressif pour tout capturer.
--    Les signaux non pris sont simulés avec la même gestion (v2.51 : 1re minute et partiels corrigés).
SELECT model, session, COUNT(*) AS n,
       ROUND(AVG(outcome = 'WIN'), 2) AS winrate,
       ROUND(AVG(r_multiple), 2)      AS esperance_R,
       ROUND(SUM(r_multiple), 1)      AS total_R,
       ROUND(AVG(mfe_r), 2)           AS mfe_moyen
FROM signals
WHERE filled = 1 AND outcome IN ('WIN', 'LOSS', 'BE')
GROUP BY model, session HAVING n >= 20
ORDER BY esperance_R DESC;

-- 2. Le biais journalier aide-t-il ? (même requête, séparée selon l'alignement avec le biais de la veille)
SELECT CASE WHEN daily_bias = 0 THEN 'pas de biais'
            WHEN daily_bias = direction THEN 'avec le biais' ELSE 'contre le biais' END AS alignement,
       COUNT(*) AS n, ROUND(AVG(outcome = 'WIN'), 2) AS winrate, ROUND(AVG(r_multiple), 2) AS esperance_R
FROM signals
WHERE filled = 1 AND outcome IN ('WIN', 'LOSS', 'BE')
GROUP BY alignement ORDER BY esperance_R DESC;

-- 3. Les cibles inventées valent-elles quelque chose ? (DOL = liquidité / STD réelle, CAP = DOL plafonnée, FALLBACK = R fixe)
SELECT tp_source, COUNT(*) AS n, ROUND(AVG(outcome = 'WIN'), 2) AS winrate, ROUND(AVG(r_multiple), 2) AS esperance_R
FROM signals
WHERE filled = 1 AND outcome IN ('WIN', 'LOSS', 'BE')
GROUP BY tp_source ORDER BY esperance_R DESC;

-- 4. Break-even à 1R : combien de sorties « BE » avaient déjà fait au moins 1R de MFE ?
--    Le MFE s'arrête à la sortie : la réponse définitive vient d'un backtest A/B InpBEAtR = 1 contre InpBEAtR = 0.
SELECT model, COUNT(*) AS sorties_BE, ROUND(AVG(mfe_r), 2) AS mfe_moyen, ROUND(AVG(planned_rr), 2) AS rr_prevu
FROM signals
WHERE filled = 1 AND outcome = 'BE'
GROUP BY model ORDER BY sorties_BE DESC;

-- 5. Lot minimum : trades dont les partiels étaient impossibles (gestion « tout à la cible »)
SELECT model, COUNT(*) AS n, ROUND(AVG(r_multiple), 2) AS esperance_R
FROM signals
WHERE partial_ok = 0 AND filled = 1 AND outcome IN ('WIN', 'LOSS', 'BE')
GROUP BY model;
