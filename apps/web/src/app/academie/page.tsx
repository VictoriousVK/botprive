import type { Metadata } from "next";
import { AcademyView } from "./view";

export const metadata: Metadata = { title: "Académie", description: "Cours vidéo en plusieurs parties : débutant, gestion du risque, méthode ICT." };

export default function Page() {
  return <AcademyView />;
}
