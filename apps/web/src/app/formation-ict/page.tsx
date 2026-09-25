import type { Metadata } from "next";
import { FormationView } from "./view";

export const metadata: Metadata = {
  title: "Victorious Trader : formation ICT",
  description: "Programme officiel de formation ICT par Victor Faye : 16 modules, de l'IPDA au Friday Model, cas réels sur NAS100, XAUUSD et EURUSD, accès à vie au groupe d'élite.",
};

export default function Page() {
  return <FormationView />;
}
