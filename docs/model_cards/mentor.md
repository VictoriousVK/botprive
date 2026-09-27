# Mentor

**But.** Répondre aux questions de cours à partir des contenus de la formation : fiches, définitions,
transcriptions, cours de l'académie. Il cite ses sources, horodatage vidéo compris quand il existe.

**Hors périmètre.** Il ne répond pas hors des contenus (`OUT_OF_CORPUS`) et ne donne aucun conseil
personnalisé ni signal (`REFUSED_ADVICE`, avec un renvoi vers le cours).

- **Recherche.** BM25 sur les passages, **filtrée par les droits du membre avant le classement** :
  un module payant ne fuit jamais dans la réponse d'un membre gratuit.
- **Sortie.** `MentorAnswer` : label, réponse, citations (identifiants de passages vérifiés parmi
  ceux fournis), exercice facultatif.
- **Modèle.** `mentor` (Sonnet 5), prompt `prompts/mentor.md`. Budget : 2 appels, 20 000 jetons en
  entrée, 45 s.
- **Vérifications.** Une réponse sans citation valide est remplacée par l'extrait des passages. Les
  nombres doivent figurer dans les passages. Le garde-fou de sortie s'applique.
- **Tests.** `tests/test_saas_p1.py` (accès, citations, refus de conseil), scorecard.
- **Limites connues.** La qualité dépend de la base de connaissances (`/admin/` → SaaS IA) ; les
  transcriptions des vidéos restent à importer.
