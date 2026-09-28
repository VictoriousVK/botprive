import Link from "next/link";

export default function NotFound() {
  return (
    <div className="container-x grid min-h-[60vh] place-items-center py-20 text-center">
      <div>
        <p className="num text-6xl font-semibold text-brand-300">404</p>
        <h1 className="mt-4 font-[family-name:var(--font-display)] text-2xl font-bold">Page introuvable</h1>
        <p className="mt-2 text-muted">Cette page n&apos;existe pas ou a été déplacée.</p>
        <Link href="/" className="btn btn-primary mt-8">Retour à l&apos;accueil</Link>
      </div>
    </div>
  );
}
