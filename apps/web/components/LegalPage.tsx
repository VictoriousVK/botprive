import { readFileSync } from "node:fs";
import path from "node:path";
import { renderMarkdown } from "@/lib/markdown";

/** Page légale rendue depuis content/legal/<slug>.md (modifiable sans toucher au code). */
export function LegalPage({ slug }: { slug: "cgv" | "confidentialite" | "remboursement" }) {
  const source = readFileSync(path.join(process.cwd(), "content/legal", `${slug}.md`), "utf8");
  return (
    <div className="container page">
      <article className="prose" dangerouslySetInnerHTML={{ __html: renderMarkdown(source) }} />
    </div>
  );
}
