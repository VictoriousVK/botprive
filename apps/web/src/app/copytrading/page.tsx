import type { Metadata } from "next";
import { CopyView } from "./view";

export const metadata: Metadata = { title: "Copytrading", description: "Copiez une stratégie en démo, avec votre capital, votre multiplicateur et votre seuil de perte." };

export default function Page() {
  return <CopyView />;
}
