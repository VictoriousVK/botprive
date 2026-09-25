import type { Metadata } from "next";
import { TarifsView } from "./view";

export const metadata: Metadata = { title: "Offres et paiement Wave", description: "Découverte, Trader, Pro, Elite : offres en FCFA, payées avec Wave." };

export default function Page() {
  return <TarifsView />;
}
