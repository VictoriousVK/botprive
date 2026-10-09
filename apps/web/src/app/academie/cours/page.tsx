import type { Metadata } from "next";
import { Suspense } from "react";
import { Spinner } from "@/components/ui";
import { CourseView } from "./view";

export const metadata: Metadata = { title: "Cours" };

export default function Page() {
  return (
    <Suspense fallback={<div className="container-x py-14"><Spinner /></div>}>
      <CourseView />
    </Suspense>
  );
}
