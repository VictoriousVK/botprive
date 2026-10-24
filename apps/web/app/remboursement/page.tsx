import type { Metadata } from "next";
import { LegalPage } from "@/components/LegalPage";

export const metadata: Metadata = { title: "Politique de remboursement" };

export default function Page() {
  return <LegalPage slug="remboursement" />;
}
