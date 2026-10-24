import Link from "next/link";
import { CLUB } from "@vk/core";

export function SiteFooter() {
  return (
    <footer className="site-footer">
      <div className="container">
        <div className="cols">
          <div>
            <p className="quote">« {CLUB.quote} »</p>
            <p className="label" style={{ marginTop: 16 }}>
              {CLUB.signatures.join(" · ")}
            </p>
          </div>
          <div>
            <p className="label">Le club</p>
            <ul style={{ marginTop: 12 }}>
              <li><a href="/#formules">Formules</a></li>
              <li><a href="/#faq">Questions fréquentes</a></li>
              <li><Link href="/espace">Espace membre</Link></li>
              <li><a href={`https://wa.me/${CLUB.whatsappNumber.replace("+", "")}`} rel="noopener noreferrer">WhatsApp</a></li>
            </ul>
          </div>
          <div>
            <p className="label">Informations</p>
            <ul style={{ marginTop: 12 }}>
              <li><Link href="/cgv">Conditions générales de vente</Link></li>
              <li><Link href="/remboursement">Politique de remboursement</Link></li>
              <li><Link href="/confidentialite">Confidentialité</Link></li>
            </ul>
          </div>
        </div>
        <p className="disclaimer">
          Le trading comporte un risque élevé de perte en capital. Les contenus du Live Club sont éducatifs et ne constituent pas un
          conseil en investissement. Les performances passées ne préjugent pas des performances futures.
        </p>
        <p className="disclaimer">© {new Date().getFullYear()} V_ICT_ORIOUS · Victor Faye · Sénégal</p>
      </div>
    </footer>
  );
}
