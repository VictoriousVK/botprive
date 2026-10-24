import Link from "next/link";

export default function NotFound() {
  return (
    <div className="container page page-narrow">
      <p className="label">Erreur 404</p>
      <h1 className="display" style={{ fontSize: "clamp(2.6rem, 11vw, 4.6rem)" }}>
        Page introuvable
      </h1>
      <Link className="btn" href="/">
        Retour à l'accueil
      </Link>
    </div>
  );
}
