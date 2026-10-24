import Link from "next/link";

export function SiteHeader() {
  return (
    <header className="site-header">
      <div className="container bar">
        <Link href="/" className="brand" aria-label="V_ICT_ORIOUS, accueil">
          V_ICT_<span>ORIOUS</span>
        </Link>
        <nav className="nav" aria-label="Navigation principale">
          <a className="nav-link" href="/#planning">Planning</a>
          <a className="nav-link" href="/#avantages">Avantages</a>
          <a className="nav-link" href="/#formules">Formules</a>
          <a className="nav-link" href="/#faq">FAQ</a>
          <Link className="btn small ghost" href="/espace">
            Espace membre
          </Link>
        </nav>
      </div>
    </header>
  );
}
