---
name: prop-firm-profiles
description: Comment encoder, dater et vérifier un profil de règles de prop firm (config/prop_firms.yaml). À lire avant d'ajouter ou de modifier un profil.
---

# Profils prop firm

- Un profil = une firme + un programme + une date de vérification + l'URL du règlement officiel.
- Champs : perte journalière (pourcentage, base : solde ou equity du début de journée, heure et fuseau de
  réinitialisation), perte maximale (statique ou suiveuse), objectif de profit, jours minimum, règles sur
  les news (minutes avant/après), week-end, EA autorisés, copie de signaux interdite.
- **`verified_at: null` tant qu'une personne n'a pas relu le règlement officiel** : le garde-fou affiche
  alors « profil à vérifier » et reste utilisable, mais le membre est prévenu.
- Revue mensuelle et à chaque annonce de la firme. Un profil modifié garde son historique (nouvelle
  version), pour expliquer une alerte passée.
- Le garde-fou n'aide jamais à contourner une règle (copie de signaux, partage de compte, latence).
