/** Messages d'erreur affichés après une redirection (code → texte, jamais de texte libre dans l'URL). */
export const ERROR_MESSAGES: Record<string, string> = {
  auto_renew_card_only: "Le renouvellement automatique n'est possible que par carte bancaire.",
  consent_required: "Coche la case d'accord pour activer le prélèvement automatique.",
  method_unavailable: "Ce moyen de paiement n'est pas encore disponible.",
  auto_renew_unavailable: "Le renouvellement automatique n'est pas disponible avec ce moyen de paiement.",
  auto_renewal_active: "Ton renouvellement par carte est actif : il sera prélevé automatiquement. Annule-le d'abord dans ton espace si tu veux payer autrement.",
  email_required: "Ton adresse email est nécessaire pour le reçu et les rappels.",
  invalid_form: "Formulaire incomplet : vérifie les champs.",
  provider_error: "Le prestataire de paiement ne répond pas. Réessaie dans quelques minutes.",
  not_cancelable: "Il n'y a pas de renouvellement à annuler.",
  provider_subscription_unknown: "Annulation automatique impossible pour le moment : contacte-nous sur WhatsApp, nous l'annulons manuellement.",
  oauth_failed: "La connexion Discord a échoué. Réessaie.",
  oauth_denied: "Connexion Discord annulée.",
  link_invalid: "Ce lien de renouvellement a expiré. Connecte-toi pour renouveler.",
  csrf: "Requête refusée. Recharge la page et réessaie.",
};

export function errorMessage(code: string | undefined): string | null {
  if (!code) return null;
  return ERROR_MESSAGES[code] ?? "Une erreur est survenue. Réessaie.";
}
