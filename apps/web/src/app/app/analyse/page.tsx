import type { Metadata } from "next";
import { Suspense } from "react";
import { Spinner } from "@/components/ui";
import { AnalysisView } from "./view";

export const metadata: Metadata = { title: "Analyse de setup ICT", robots: { index: false } };

export default function Page() {
  return (
    <Suspense fallback={<div className="container-x py-14"><Spinner /></div>}>
      <AnalysisView />
    </Suspense>
  );
}
