import type { Metadata } from "next";
import { Suspense } from "react";
import { Spinner } from "@/components/ui";
import { ResetView } from "./view";

export const metadata: Metadata = { title: "Nouveau mot de passe", robots: { index: false } };

export default function Page() {
  return (
    <Suspense fallback={<div className="container-x py-14"><Spinner /></div>}>
      <ResetView />
    </Suspense>
  );
}
