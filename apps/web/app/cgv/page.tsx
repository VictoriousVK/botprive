import type { Metadata } from "next";
import { LegalPage } from "@/components/LegalPage";

export const metadata: Metadata = { title: "Conditions générales de vente" };

export default function Page() {
  return <LegalPage slug="cgv" />;
}
