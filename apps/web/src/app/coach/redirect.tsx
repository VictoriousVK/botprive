"use client";

import { ArrowRight, GraduationCap } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect } from "react";

export function CoachRedirect() {
  const router = useRouter();
  useEffect(() => {
    router.replace("/app/mentor/");
  }, [router]);
  return (
    <div className="container-x grid min-h-[60vh] place-items-center py-14">
      <div className="card w-full max-w-md p-8 text-center">
        <div className="mx-auto grid size-12 place-items-center rounded-2xl bg-brand-500/15 text-brand-300"><GraduationCap className="size-6" aria-hidden /></div>
        <h1 className="mt-4 font-[family-name:var(--font-display)] text-xl font-bold">Le coach ICT s&apos;appelle désormais le Mentor</h1>
        <p className="mt-2 text-sm text-muted">Vos questions sur ICT se posent dans l&apos;espace de trading. Redirection…</p>
        <Link href="/app/mentor/" className="btn btn-primary mt-6">Ouvrir le Mentor <ArrowRight className="size-4" aria-hidden /></Link>
      </div>
    </div>
  );
}
