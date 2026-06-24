import type {
  SymbolGraph, SymbolGraphSymbol, DeclarationFragment,
} from "./symbol-graph.js";
import type {
  TypeDocProject, TypeDocDeclaration, TypeDocSignature,
  TypeDocParameter, TypeDocType, TypeDocKind, CommentBlockTag,
} from "./typedoc-types.js";
import { KIND_STRING } from "./typedoc-types.js";
import { parseDocComment } from "./doc-comment.js";

const KIND_MAP: Record<string, TypeDocKind> = {
  "swift.class": 128, "swift.struct": 128, "swift.protocol": 256,
  "swift.enum": 8, "swift.enum.case": 16, "swift.init": 512,
  "swift.method": 2048, "swift.property": 1024,
  "swift.func": 64, "swift.typealias": 2097152, "swift.var": 32,
};

const INTRINSICS = new Set([
  "String", "Int", "Int8", "Int16", "Int32", "Int64",
  "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
  "Double", "Float", "Bool", "Void", "Never", "Any", "AnyObject",
]);

export function parseTypeString(text: string, genericParams: Set<string> = new Set()): TypeDocType {
  const t = text.trim();
  if (t.endsWith("?")) {
    return {
      type: "union",
      types: [parseTypeString(t.slice(0, -1), genericParams), { type: "intrinsic", name: "undefined" }],
    };
  }
  if (t.startsWith("Optional<") && t.endsWith(">")) {
    return {
      type: "union",
      types: [parseTypeString(t.slice(9, -1), genericParams), { type: "intrinsic", name: "undefined" }],
    };
  }
  if (t.startsWith("[") && t.endsWith("]")) {
    const inner = t.slice(1, -1).trim();
    const colonIdx = findTopLevelColon(inner);
    if (colonIdx >= 0) {
      return {
        type: "reference", name: "Dictionary",
        typeArguments: [
          parseTypeString(inner.slice(0, colonIdx).trim(), genericParams),
          parseTypeString(inner.slice(colonIdx + 1).trim(), genericParams),
        ],
      };
    }
    return { type: "array", elementType: parseTypeString(inner, genericParams) };
  }
  if (t.startsWith("Array<") && t.endsWith(">")) {
    return { type: "array", elementType: parseTypeString(t.slice(6, -1), genericParams) };
  }
  if (genericParams.has(t)) return { type: "typeParameter", name: t };
  if (INTRINSICS.has(t)) return { type: "intrinsic", name: t };
  return { type: "reference", name: t };
}

function findTopLevelColon(s: string): number {
  let depth = 0;
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (c === "<" || c === "[" || c === "(") depth++;
    else if (c === ">" || c === "]" || c === ")") depth--;
    else if (c === ":" && depth === 0) return i;
  }
  return -1;
}

function parseFragments(frags: DeclarationFragment[] | undefined, gp: Set<string>): TypeDocType {
  if (!frags?.length) return { type: "intrinsic", name: "Void" };
  return parseTypeString(frags.map(f => f.spelling).join("").trim(), gp);
}

function baseName(title: string): string {
  const i = title.indexOf("(");
  return i >= 0 ? title.slice(0, i) : title;
}

function buildSignature(
  sym: SymbolGraphSymbol,
  genericParams: Set<string>,
  getId: () => number,
): TypeDocSignature {
  const fs = sym.functionSignature!;
  const name = baseName(sym.names.title);
  const comment = sym.docComment?.lines.length
    ? parseDocComment(sym.docComment.lines) : undefined;

  const paramDocs = new Map<string, string>();
  for (const tag of comment?.blockTags ?? []) {
    if (tag.tag === "@param" && tag.name) {
      paramDocs.set(tag.name, tag.content.map(c => c.text).join(""));
    }
  }

  const parameters: TypeDocParameter[] = (fs.parameters ?? []).map(p => {
    const docText = paramDocs.get(p.name);
    return {
      id: getId(),
      name: p.name,
      kind: 32768 as const,
      kindString: "Parameter" as const,
      flags: {} as Record<string, never>,
      ...(docText && { comment: { summary: [{ kind: "text" as const, text: docText }] } }),
      type: parseFragments(p.declarationFragments, genericParams),
    };
  });

  const hasComment = comment && (comment.summary.length > 0 || (comment.blockTags?.length ?? 0) > 0);

  return {
    id: getId(),
    name,
    kind: 4096 as const,
    kindString: "Call signature" as const,
    flags: {},
    ...(hasComment && { comment }),
    ...(parameters.length > 0 && { parameters }),
    type: parseFragments(fs.returns, genericParams),
  };
}

export function transformSymbolGraph(
  graphs: SymbolGraph[],
  moduleName: string,
  categoryMap: Record<string, string> = {},
): TypeDocProject {
  let nextId = 1;
  const getId = () => nextId++;

  const allSymbols = new Map<string, SymbolGraphSymbol>();
  const allRelationships: SymbolGraph["relationships"] = [];
  const symbolModule = new Map<string, string>();
  for (const g of graphs) {
    for (const s of g.symbols) {
      allSymbols.set(s.identifier.precise, s);
      symbolModule.set(s.identifier.precise, g.module.name);
    }
    allRelationships.push(...g.relationships);
  }

  const memberOf = new Map<string, string>();
  const conformsTo = new Map<string, string[]>();
  const inheritsFrom = new Map<string, string>();
  for (const rel of allRelationships) {
    if (rel.kind === "memberOf") memberOf.set(rel.source, rel.target);
    else if (rel.kind === "conformsTo") {
      const list = conformsTo.get(rel.source) ?? [];
      list.push(rel.target);
      conformsTo.set(rel.source, list);
    } else if (rel.kind === "inheritsFrom") inheritsFrom.set(rel.source, rel.target);
  }

  const publicSymbols = [...allSymbols.values()].filter(
    s => s.accessLevel === "public" || s.accessLevel === "open"
  );

  const declarations = new Map<string, TypeDocDeclaration>();
  for (const sym of publicSymbols) {
    const kind = KIND_MAP[sym.kind.identifier];
    if (!kind) continue;

    const precise = sym.identifier.precise;
    const genericParams = new Set(sym.swiftGenerics?.parameters?.map(p => p.name) ?? []);
    const isCallable = kind === 2048 || kind === 64 || kind === 512;

    const decl: TypeDocDeclaration = {
      id: getId(),
      name: baseName(sym.names.title),
      variant: "declaration",
      kind,
      kindString: KIND_STRING[kind],
      flags: {},
    };

    if (!isCallable && sym.docComment?.lines.length) {
      const comment = parseDocComment(sym.docComment.lines);
      if (comment.summary.length || comment.blockTags?.length) decl.comment = comment;
    }

    if (sym.location) {
      const uri = sym.location.uri;
      decl.sources = [{
        fileName: uri.startsWith("file://") ? uri.slice("file://".length) : uri,
        line: sym.location.position.line,
        character: sym.location.position.character,
      }];
    }

    if (isCallable && sym.functionSignature) {
      decl.signatures = [buildSignature(sym, genericParams, getId)];
    }

    if ((kind === 1024 || kind === 32) && sym.declarationFragments) {
      decl.type = parseFragments(sym.declarationFragments, genericParams);
    }

    if (genericParams.size > 0) {
      decl.typeParameter = [...genericParams].map(name => ({
        id: getId(), name, kind: 131072 as const, kindString: "Type parameter" as const,
        flags: {} as Record<string, never>,
      }));
    }

    const conforms = conformsTo.get(precise);
    if (conforms?.length) {
      decl.implementedTypes = conforms.map(p => ({
        type: "reference" as const,
        name: allSymbols.get(p)?.names.title ?? p,
      }));
    }

    const superclass = inheritsFrom.get(precise);
    if (superclass) {
      decl.extendedTypes = [{
        type: "reference",
        name: allSymbols.get(superclass)?.names.title ?? superclass,
      }];
    }

    const modName = symbolModule.get(precise);
    const category = modName ? categoryMap[modName] : undefined;
    if (category) {
      const tag: CommentBlockTag = { tag: "@category", content: [{ kind: "text", text: category }] };
      if (decl.comment) {
        decl.comment = { ...decl.comment, blockTags: [...(decl.comment.blockTags ?? []), tag] };
      } else {
        decl.comment = { summary: [], blockTags: [tag] };
      }
    }

    declarations.set(precise, decl);
  }

  const rootChildren: TypeDocDeclaration[] = [];
  for (const sym of publicSymbols) {
    const decl = declarations.get(sym.identifier.precise);
    if (!decl) continue;
    const parentPrecise = memberOf.get(sym.identifier.precise);
    if (parentPrecise) {
      const parent = declarations.get(parentPrecise);
      if (parent) {
        parent.children = parent.children ?? [];
        parent.children.push(decl);
        continue;
      }
    }
    rootChildren.push(decl);
  }

  return { id: 0, name: moduleName, kind: 1, kindString: "Project", flags: {}, children: rootChildren };
}
