import type { Metadata } from "next";
import { CoachRedirect } from "./redirect";

// The ICT questions are answered by the Mentor of the trading space (/app/mentor/), from the ICT
// reference sheets and the courses. This address stays for the links already shared.
export const metadata: Metadata = {
  title: "Questions ICT : le Mentor IA",
  description: "Vos questions sur ICT (order blocks, FVG, liquidité, structure, killzones, Silver Bullet) trouvent leur réponse dans le Mentor IA de l'espace de trading, avec les sources affichées.",
  robots: { index: false },
};

export default function Page() {
  return <CoachRedirect />;
}
