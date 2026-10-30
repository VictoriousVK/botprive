// Minimal, safe Markdown for the coach's answers: headings, paragraphs, lists, **bold**,
// *italic*, `code` and tables. Builds React elements (no HTML injection possible).
import { Fragment, type ReactNode } from "react";

function inline(text: string, key: string): ReactNode[] {
  const out: ReactNode[] = [];
  const re = /(\*\*[^*]+\*\*|`[^`]+`|\*[^*\s][^*]*\*)/g;
  let last = 0;
  let m: RegExpExecArray | null;
  let i = 0;
  while ((m = re.exec(text))) {
    if (m.index > last) out.push(text.slice(last, m.index));
    const t = m[0];
    const k = `${key}-${i++}`;
    if (t.startsWith("**")) out.push(<strong key={k} className="font-semibold text-white">{t.slice(2, -2)}</strong>);
    else if (t.startsWith("`")) out.push(<code key={k} className="num rounded bg-white/[0.06] px-1 py-0.5 text-[0.9em] text-brand-300">{t.slice(1, -1)}</code>);
    else out.push(<em key={k}>{t.slice(1, -1)}</em>);
    last = m.index + t.length;
  }
  if (last < text.length) out.push(text.slice(last));
  return out;
}

export function Markdown({ text }: { text: string }) {
  const lines = text.replace(/\r/g, "").split("\n");
  const blocks: ReactNode[] = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    const k = `b${i}`;
    if (!line.trim()) {
      i++;
      continue;
    }
    const h = /^(#{1,4})\s+(.*)$/.exec(line);
    if (h) {
      blocks.push(<p key={k} className="mt-4 font-[family-name:var(--font-display)] text-[0.95rem] font-bold text-white first:mt-0">{inline(h[2], k)}</p>);
      i++;
      continue;
    }
    if (/^\s*\|.*\|\s*$/.test(line)) {
      const rows: string[][] = [];
      while (i < lines.length && /^\s*\|.*\|\s*$/.test(lines[i])) {
        if (!/^\s*\|[\s:|-]+\|\s*$/.test(lines[i])) rows.push(lines[i].trim().slice(1, -1).split("|").map((c) => c.trim()));
        i++;
      }
      blocks.push(
        <div key={k} className="scroll-x mt-3"><table className="table text-sm">
          <thead><tr>{rows[0]?.map((c, j) => <th key={j}>{inline(c, `${k}h${j}`)}</th>)}</tr></thead>
          <tbody>{rows.slice(1).map((r, ri) => <tr key={ri}>{r.map((c, j) => <td key={j}>{inline(c, `${k}r${ri}${j}`)}</td>)}</tr>)}</tbody>
        </table></div>,
      );
      continue;
    }
    const ordered = /^\s*\d+[.)]\s+/.test(line);
    if (ordered || /^\s*[-*•]\s+/.test(line)) {
      const items: string[] = [];
      const re = ordered ? /^\s*\d+[.)]\s+/ : /^\s*[-*•]\s+/;
      while (i < lines.length && re.test(lines[i])) items.push(lines[i++].replace(re, ""));
      const Tag = ordered ? "ol" : "ul";
      blocks.push(
        <Tag key={k} className={`mt-2 grid gap-1.5 pl-5 ${ordered ? "list-decimal" : "list-disc"} marker:text-brand-400`}>
          {items.map((it, j) => <li key={j}>{inline(it, `${k}-${j}`)}</li>)}
        </Tag>,
      );
      continue;
    }
    const para: string[] = [];
    while (i < lines.length && lines[i].trim() && !/^(#{1,4}\s|\s*[-*•]\s|\s*\d+[.)]\s|\s*\|)/.test(lines[i])) para.push(lines[i++]);
    blocks.push(<p key={k} className="mt-2 first:mt-0">{para.map((p, j) => <Fragment key={j}>{j > 0 && <br />}{inline(p, `${k}-${j}`)}</Fragment>)}</p>);
  }
  return <div className="text-[0.94rem] leading-relaxed text-fg/90">{blocks}</div>;
}
