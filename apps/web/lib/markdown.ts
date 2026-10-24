/*
 * Mini-rendu Markdown pour les pages légales (titres, paragraphes, listes, citations, gras, liens).
 * Le contenu vient de nos propres fichiers (content/legal) ; il est tout de même échappé.
 */

function escapeHtml(value: string): string {
  return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

function inline(text: string): string {
  return escapeHtml(text)
    .replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
    .replace(/\[([^\]]+)\]\(((?:https?:\/\/|\/|mailto:)[^)\s]+)\)/g, '<a href="$2">$1</a>');
}

export function renderMarkdown(source: string): string {
  const out: string[] = [];
  let list: string[] | null = null;
  let paragraph: string[] = [];
  const flush = () => {
    if (paragraph.length) out.push(`<p>${inline(paragraph.join(" "))}</p>`);
    paragraph = [];
    if (list) out.push(`<ul>${list.map((li) => `<li>${inline(li)}</li>`).join("")}</ul>`);
    list = null;
  };
  for (const raw of source.split(/\r?\n/)) {
    const line = raw.trimEnd();
    const heading = /^(#{1,3})\s+(.*)$/.exec(line);
    if (heading) {
      flush();
      const level = heading[1]!.length;
      out.push(`<h${level}>${inline(heading[2]!)}</h${level}>`);
    } else if (/^[-*]\s+/.test(line)) {
      if (paragraph.length) {
        out.push(`<p>${inline(paragraph.join(" "))}</p>`);
        paragraph = [];
      }
      (list ??= []).push(line.replace(/^[-*]\s+/, ""));
    } else if (/^>\s?/.test(line)) {
      flush();
      out.push(`<blockquote>${inline(line.replace(/^>\s?/, ""))}</blockquote>`);
    } else if (line.trim() === "") {
      flush();
    } else {
      if (list) flush();
      paragraph.push(line.trim());
    }
  }
  flush();
  return out.join("\n");
}
