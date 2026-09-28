import type { Metadata } from "next";
import { TarifsView } from "./view";

export const metadata: Metadata = { title: "Offres et paiement Wave", description: "Starter, Pro Trader, Quant Elite, formation ICT Victorious Trader, mentorat : payés avec Wave." };

export default function Page() {
  return <TarifsView />;
}
