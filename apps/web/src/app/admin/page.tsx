import type { Metadata } from "next";
import { AdminView } from "./view";

export const metadata: Metadata = { title: "Administration", robots: { index: false } };

export default function Page() {
  return <AdminView />;
}
