import type { TypeDocComment, CommentContent, CommentBlockTag } from "./typedoc-types.js";

const PARAM_RE = /^-\s+Parameter\s+(\w+):\s*(.*)/i;
const RETURNS_RE = /^-\s+Returns:\s*(.*)/i;
const THROWS_RE = /^-\s+Throws:\s*(.*)/i;
const DASH_TAG_RE = /^-\s+(\w+):\s*(.*)/i;
const DOCC_PARAM_RE = /^@Parameter\s+(\w+)\s+(.*)/i;
const DOCC_RETURNS_RE = /^@Returns\s+(.*)/i;
const DOCC_THROWS_RE = /^@Throws\s+(.*)/i;
const DOCC_TAG_RE = /^@(\w+)\s+(.*)/i;

function isTagLine(t: string): boolean {
  return (
    PARAM_RE.test(t) || RETURNS_RE.test(t) || THROWS_RE.test(t) ||
    DASH_TAG_RE.test(t) || DOCC_PARAM_RE.test(t) || DOCC_RETURNS_RE.test(t) ||
    DOCC_THROWS_RE.test(t) || DOCC_TAG_RE.test(t)
  );
}

function parseTagLine(t: string): CommentBlockTag | null {
  let m: RegExpExecArray | null;

  m = PARAM_RE.exec(t) ?? DOCC_PARAM_RE.exec(t);
  if (m) return { tag: "@param", name: m[1], content: [{ kind: "text", text: m[2] }] };

  m = RETURNS_RE.exec(t) ?? DOCC_RETURNS_RE.exec(t);
  if (m) return { tag: "@returns", content: [{ kind: "text", text: m[1] }] };

  m = THROWS_RE.exec(t) ?? DOCC_THROWS_RE.exec(t);
  if (m) return { tag: "@throws", content: [{ kind: "text", text: m[1] }] };

  m = DASH_TAG_RE.exec(t);
  if (m) return { tag: `@${m[1].toLowerCase()}`, content: [{ kind: "text", text: m[2] }] };

  m = DOCC_TAG_RE.exec(t);
  if (m) return { tag: `@${m[1].toLowerCase()}`, content: [{ kind: "text", text: m[2] }] };

  return null;
}

export function parseDocComment(lines: Array<{ text: string }>): TypeDocComment {
  const summary: CommentContent[] = [];
  const blockTags: CommentBlockTag[] = [];
  let inTags = false;

  for (const { text: raw } of lines) {
    const t = raw.trim();

    if (!inTags && !isTagLine(t)) {
      if (t) summary.push({ kind: "text", text: t });
      continue;
    }

    if (!isTagLine(t)) continue; // non-tag lines after first tag are inter-tag content, not summary

    inTags = true;
    const tag = parseTagLine(t);
    if (tag) blockTags.push(tag);
  }

  return blockTags.length > 0 ? { summary, blockTags } : { summary };
}
