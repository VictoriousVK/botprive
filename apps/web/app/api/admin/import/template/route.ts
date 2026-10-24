import { IMPORT_TEMPLATE_CSV } from "@vk/core";

export const dynamic = "force-static";

/** Modèle CSV à remplir (exemples fictifs). */
export function GET() {
  return new Response(`﻿${IMPORT_TEMPLATE_CSV}`, {
    headers: { "content-type": "text/csv; charset=utf-8", "content-disposition": 'attachment; filename="modele-import-membres.csv"' },
  });
}
