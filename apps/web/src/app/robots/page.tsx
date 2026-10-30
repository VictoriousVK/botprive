import type { Metadata } from "next";
import { RobotsView } from "./view";

export const metadata: Metadata = { title: "Robots de trading MT5", description: "ICT Ultimate Pro v6.20 et ICT v6 : nos Expert Advisors portés sur la plateforme, en bêta." };

export default function Page() {
  return <RobotsView />;
}
