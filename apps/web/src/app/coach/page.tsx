import type { Metadata } from "next";
import { CoachView } from "./view";

export const metadata: Metadata = {
  title: "Coach IA ICT",
  description: "Posez vos questions sur ICT : order blocks, FVG, liquidité, structure, killzones, Silver Bullet. Réponses sourcées depuis la base de la formation Victorious Trader.",
};

export default function Page() {
  return <CoachView />;
}
