# Research : briefing de pré-session (graphe G4)

**But.** Avant Londres et New York, résumer le contexte : annonces économiques à fort impact, régime
de marché (règles sur les séries de prix) et actualités pertinentes.

**Hors périmètre.** Il n'annonce pas de direction de prix et ne recommande aucun trade.

- **Graphe.** plan → [calendrier ‖ séries de prix ‖ actualités] → validation (nouveau plan si des
  données manquent) → synthèse.
- **Sortie.** `Briefing` :
  - label `RISK_ON`, `RISK_OFF`, `NEUTRAL` ou `INSUFFICIENT_EVIDENCE`, fixé par les règles de
    régime ;
  - annonces, actualités retenues ;
  - avertissement quand une seule source rapporte une information.
- **Modèle.** `research` (Sonnet 5) pour le résumé et le tri des actualités, prompt
  `prompts/research.md`. Budget : 2 appels, 120 s.
- **Déclenchement.** n8n (`/api/jobs/briefing`) ou `/admin/` → SaaS IA. Diffusion Telegram aux membres
  qui l'ont activée.
- **Tests.** `tests/test_saas_p1.py`.
- **Limites connues.** Le calendrier et les actualités sont importés ou issus de sources à licencier.
  Sans données, le briefing le dit.
