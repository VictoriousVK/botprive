import type { Metadata } from "next";
import { Suspense } from "react";
import { Spinner } from "@/components/ui";
import { VerifyView } from "./view";

export const metadata: Metadata = { title: "Confirmation de l'adresse e-mail", robots: { index: false } };

export default function Page() {
  return (
    <Suspense fallback={<div className="container-x py-14"><Spinner /></div>}>
      <VerifyView />
    </Suspense>
  );
}
