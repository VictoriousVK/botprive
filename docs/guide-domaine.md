# Nom de domaine : options et coûts

> **N'achète rien avant d'avoir choisi** : un domaine se renouvelle chaque année, et le prix de renouvellement
> compte plus que la promotion de la première année. Prix relevés en octobre 2026 (sources tierces pour la plupart), à vérifier au moment de l'achat.

## En attendant : gratuit
Railway fournit une adresse gratuite du type `victorious-club.up.railway.app`, suffisante pour les tests.
**Limite** : l'envoi d'emails (Resend) exige un domaine à toi. Sans domaine, les emails ne partent que vers ta propre adresse ; les rappels Discord fonctionnent quand même.

## Options

| Extension | Où | 1re année | Renouvellement / an | Remarques |
|---|---|---|---|---|
| **.com** | Cloudflare Registrar | ~10,46 $ | ~10,46 $ (prix coûtant, hausse du tarif de gros annoncée au 1er novembre 2026) | Universel et crédible. Nécessite un compte Cloudflare |
| .com | Namecheap, Porkbun… | promos variables | ~11 à 15 $ | Interface simple |
| **.club** | Porkbun | ~4 $ | ~16 $ | Colle au « Live Club » |
| .club | Namecheap | 20,98 $ | 24,98 $ | Prix officiel depuis le 1er avril 2026 |
| **.sn** | Registrars sénégalais (ex. nom-domaine.sn, Gouyhost) | ~18 400 à 26 000 FCFA | idem | Identité locale ; une adresse au Sénégal peut être exigée pour un particulier |
| .sn | Registrars internationaux | 36 $ à plus de 140 € | idem | Beaucoup plus cher, inutile depuis le Sénégal |

En FCFA (≈ 575 FCFA/$) : un .com revient à environ 6 000 FCFA par an, un .club à environ 9 000 FCFA par an après la première année, un .sn à 18 000 à 26 000 FCFA par an.

## Recommandation
- **.com chez Cloudflare** : le meilleur rapport crédibilité / prix, et un renouvellement stable. Exemples à vérifier : `victoriousliveclub.com`, `victorious-club.com`, `victorfaye-trading.com`.
- Variante plus « marque » : **.club** (`victorious.club`, `victoriouslive.club`), mais renouvellement plus cher que .com.
- **.sn** si tu veux afficher l'ancrage sénégalais (`victorious.sn`) et que tu as une adresse au Sénégal.

Avant l'achat : vérifie la disponibilité chez le registrar, évite les tirets multiples et les fautes probables, et regarde aussi le nom sur Instagram, TikTok et Telegram.

## Après l'achat (je t'accompagne)
1. Railway → service `web` → Custom Domain → `club.ton-domaine.com` (ou le domaine nu).
2. Chez le registrar : enregistrement **CNAME** indiqué par Railway. Le HTTPS est automatique.
3. Resend → Add Domain → enregistrements **SPF / DKIM** à ajouter (envoi des emails).
4. Variables : `APP_URL=https://club.ton-domaine.com`, `EMAIL_FROM=V_ICT_ORIOUS Live Club <club@ton-domaine.com>`.
5. Mise à jour des URLs chez Discord (redirect OAuth) et chez le prestataire de paiement (webhook).

## Sources
- [Cloudflare .com, suivi des prix (domainoffer.net)](https://domainoffer.net/tld/com/cloudflare) · [Comparateur (costgoat.com)](https://costgoat.com/compare/domains)
- [Namecheap : hausse des prix .club](https://www.namecheap.com/blog/price-increase-for-biz-club-vip-and-more-domains/) · [Porkbun .club (domainoffer.net)](https://domainoffer.net/tld/club/porkbun)
- [.sn chez nom-domaine.sn](http://www.nom-domaine.sn/) · [Gouyhost](https://gouyhost.sn/nom-domaine/achat) · [bNamed (conditions .sn)](https://www.bnamed.net/fr/extensies/S%C3%A9n%C3%A9gal) · [Netim](https://www.netim.com/en/domain-name/sn-domain) · [.sn ou .com (Kolonell)](https://kolonell.com/en/blog/domain-name-sn-com-how-to-choose-2026)
