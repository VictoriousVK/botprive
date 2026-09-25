import type { Metadata } from "next";

export const metadata: Metadata = { title: "Avertissement sur les risques et conditions" };

export default function Page() {
  return (
    <div className="container-x max-w-3xl py-14">
      <p className="eyebrow">Informations légales</p>
      <h1 className="h-section mt-3">Avertissement sur les risques</h1>
      <p className="mt-3 rounded-xl border border-gold-400/30 bg-gold-400/5 px-4 py-3 text-sm text-gold-300">
        Projet de texte à faire valider par un avocat avant l&apos;ouverture publique.
      </p>
      <div className="prose-lf mt-6">
        <p>
          Le trading de produits à effet de levier (CFD, forex, indices, métaux, cryptomonnaies) comporte un risque élevé de perte rapide en capital, pouvant
          aller jusqu&apos;à la totalité des sommes engagées. N&apos;investissez que l&apos;argent que vous pouvez vous permettre de perdre.
        </p>
        <p>
          Les résultats passés, simulés ou issus de backtests ne préjugent pas des résultats futurs. Les robots, analyses, cours et stratégies de copytrading
          proposés par Liberté Financière sont des outils et des contenus éducatifs ; ils ne constituent ni un conseil en investissement personnalisé, ni une
          garantie de gain.
        </p>
        <h2>Robots de trading</h2>
        <ul>
          <li>Les robots sont en version bêta. Testez-les d&apos;abord en simulation, puis sur compte papier et compte démo.</li>
          <li>Vous restez seul responsable de l&apos;activation d&apos;un robot sur un compte réel, protégée par trois verrous.</li>
          <li>Coupures internet, décalages de prix (slippage) et conditions de votre courtier peuvent modifier les résultats.</li>
        </ul>
        <h2>Copytrading</h2>
        <p>
          Le copytrading est proposé en démonstration : aucun ordre n&apos;est passé sur votre compte. La copie d&apos;ordres sur le compte d&apos;un client relève
          d&apos;activités réglementées (gestion pour compte de tiers, conseil en investissement). Elle ne sera ouverte qu&apos;après validation juridique et, le cas
          échéant, obtention des autorisations nécessaires auprès des autorités compétentes (AMF-UMOA pour la zone UEMOA).
        </p>
        <h2 id="conditions">Conditions d&apos;utilisation (résumé)</h2>
        <ul>
          <li>L&apos;accès payant est activé pour la durée achetée, sans renouvellement automatique.</li>
          <li>Les comptes sont personnels ; le partage d&apos;identifiants ou de vidéos est interdit.</li>
          <li>Liberté Financière ne détient jamais vos fonds de trading : ils restent chez votre courtier.</li>
        </ul>
        <h2 id="confidentialite">Confidentialité</h2>
        <p>
          Nous conservons votre nom, votre e-mail, votre numéro Wave (facultatif), l&apos;historique de vos paiements et votre progression dans les cours, pour
          fournir le service. Les mots de passe sont stockés sous forme de hachage (scrypt). Aucune donnée n&apos;est vendue. Pour toute demande d&apos;accès ou de
          suppression, contactez l&apos;équipe.
        </p>
      </div>
    </div>
  );
}
