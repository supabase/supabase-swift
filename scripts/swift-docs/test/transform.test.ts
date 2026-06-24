import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { transformSymbolGraph, parseTypeString } from "../src/transform";
import type { SymbolGraph } from "../src/symbol-graph";
import type { TypeDocDeclaration } from "../src/typedoc-types";

const here = dirname(fileURLToPath(import.meta.url));
const fixture = JSON.parse(
  readFileSync(join(here, "fixtures", "sample.symbols.json"), "utf8")
) as SymbolGraph;

// ---------------------------------------------------------------------------
// Type string parser
// ---------------------------------------------------------------------------

describe("parseTypeString", () => {
  it("maps String to intrinsic", () => {
    expect(parseTypeString("String")).toEqual({ type: "intrinsic", name: "String" });
  });
  it("maps Bool to intrinsic", () => {
    expect(parseTypeString("Bool")).toEqual({ type: "intrinsic", name: "Bool" });
  });
  it("maps T? to union with undefined", () => {
    expect(parseTypeString("String?")).toEqual({
      type: "union",
      types: [{ type: "intrinsic", name: "String" }, { type: "intrinsic", name: "undefined" }],
    });
  });
  it("maps Optional<T>", () => {
    expect(parseTypeString("Optional<String>")).toEqual({
      type: "union",
      types: [{ type: "intrinsic", name: "String" }, { type: "intrinsic", name: "undefined" }],
    });
  });
  it("maps [T] to array", () => {
    expect(parseTypeString("[String]")).toEqual({
      type: "array",
      elementType: { type: "intrinsic", name: "String" },
    });
  });
  it("maps Array<T>", () => {
    expect(parseTypeString("Array<String>")).toEqual({
      type: "array",
      elementType: { type: "intrinsic", name: "String" },
    });
  });
  it("maps [K: V] to Dictionary reference", () => {
    expect(parseTypeString("[String: Int]")).toEqual({
      type: "reference",
      name: "Dictionary",
      typeArguments: [{ type: "intrinsic", name: "String" }, { type: "intrinsic", name: "Int" }],
    });
  });
  it("maps a known generic param to typeParameter", () => {
    expect(parseTypeString("T", new Set(["T"]))).toEqual({ type: "typeParameter", name: "T" });
  });
  it("maps an unknown named type to intrinsic", () => {
    expect(parseTypeString("AuthSession")).toEqual({ type: "intrinsic", name: "AuthSession" });
  });
});

// ---------------------------------------------------------------------------
// Full transform
// ---------------------------------------------------------------------------

describe("transformSymbolGraph", () => {
  const result = transformSymbolGraph([fixture], "Auth");

  it("produces a Project root with the module name", () => {
    expect(result.id).toBe(0);
    expect(result.kind).toBe(1);
    expect(result.kindString).toBe("Project");
    expect(result.name).toBe("Auth");
  });

  it("emits AuthClient as a Class (kind 128)", () => {
    const cls = result.children.find(c => c.name === "AuthClient");
    expect(cls).toBeDefined();
    expect(cls!.kind).toBe(128);
    expect(cls!.kindString).toBe("Class");
  });

  it("puts signIn as a Method child of AuthClient", () => {
    const cls = result.children.find(c => c.name === "AuthClient")!;
    const method = cls.children?.find(c => c.name === "signIn");
    expect(method).toBeDefined();
    expect(method!.kind).toBe(2048);
    expect(method!.kindString).toBe("Method");
  });

  it("attaches doc comment summary to AuthClient", () => {
    const cls = result.children.find(c => c.name === "AuthClient")!;
    expect(cls.comment?.summary).toEqual([
      { kind: "text", text: "Manages authentication state." },
    ]);
  });

  it("attaches signIn Call signature with @param and @returns block tags", () => {
    const cls = result.children.find(c => c.name === "AuthClient")!;
    const method = cls.children?.find(c => c.name === "signIn")!;
    const sig = method.signatures?.[0];
    expect(sig).toBeDefined();
    expect(sig!.kind).toBe(4096);
    expect(sig!.comment?.blockTags?.find(t => t.tag === "@param" && t.name === "email")).toBeDefined();
    expect(sig!.comment?.blockTags?.find(t => t.tag === "@returns")).toBeDefined();
  });

  it("maps signIn parameters with String types", () => {
    const cls = result.children.find(c => c.name === "AuthClient")!;
    const sig = cls.children?.find(c => c.name === "signIn")!.signatures![0]!;
    expect(sig.parameters).toHaveLength(2);
    expect(sig.parameters![0].name).toBe("email");
    expect(sig.parameters![0].type).toEqual({ type: "intrinsic", name: "String" });
    expect(sig.parameters![1].name).toBe("password");
    expect(sig.parameters![1].type).toEqual({ type: "intrinsic", name: "String" });
  });

  it("maps signIn return type as intrinsic to AuthSession", () => {
    const cls = result.children.find(c => c.name === "AuthClient")!;
    const sig = cls.children?.find(c => c.name === "signIn")!.signatures![0]!;
    expect(sig.type).toEqual({ type: "intrinsic", name: "AuthSession" });
  });

  it("emits AuthSession as a Class (swift.struct maps to 128)", () => {
    const s = result.children.find(c => c.name === "AuthSession");
    expect(s).toBeDefined();
    expect(s!.kind).toBe(128);
  });

  it("puts token property (kind 1024) inside AuthSession", () => {
    const s = result.children.find(c => c.name === "AuthSession")!;
    const prop = s.children?.find(c => c.name === "token");
    expect(prop).toBeDefined();
    expect(prop!.kind).toBe(1024);
  });

  it("emits AuthError as Enum (kind 8)", () => {
    const e = result.children.find(c => c.name === "AuthError");
    expect(e).toBeDefined();
    expect(e!.kind).toBe(8);
  });

  it("puts invalidEmail as EnumMember (kind 16) inside AuthError", () => {
    const e = result.children.find(c => c.name === "AuthError")!;
    const member = e.children?.find(c => c.name === "invalidEmail");
    expect(member).toBeDefined();
    expect(member!.kind).toBe(16);
  });

  it("emits AuthProviderable as Interface (kind 256)", () => {
    const p = result.children.find(c => c.name === "AuthProviderable");
    expect(p).toBeDefined();
    expect(p!.kind).toBe(256);
  });

  it("adds AuthProviderable to AuthClient.implementedTypes from conformsTo", () => {
    const cls = result.children.find(c => c.name === "AuthClient")!;
    expect(cls.implementedTypes).toEqual([{ type: "reference", name: "AuthProviderable" }]);
  });

  it("attaches source file and line to AuthClient", () => {
    const cls = result.children.find(c => c.name === "AuthClient")!;
    expect(cls.sources?.[0].fileName).toContain("AuthClient.swift");
    expect(cls.sources?.[0].line).toBe(10);
  });

  it("populates extendedTypes on AuthClient from inheritsFrom relationship", () => {
    const cls = result.children.find(c => c.name === "AuthClient")!;
    expect(cls.extendedTypes).toEqual([{ type: "reference", name: "BaseAuthClient" }]);
  });

  it("maps signOut (no returns field) to Void return type with no parameters", () => {
    const cls = result.children.find(c => c.name === "AuthClient")!;
    const sig = cls.children?.find(c => c.name === "signOut")!.signatures![0]!;
    expect(sig.type).toEqual({ type: "intrinsic", name: "Void" });
    expect(sig.parameters).toBeUndefined();
  });

  it("maps refresh (no parameters field) to no parameters on signature", () => {
    const cls = result.children.find(c => c.name === "AuthClient")!;
    const sig = cls.children?.find(c => c.name === "refresh")!.signatures![0]!;
    expect(sig.parameters).toBeUndefined();
    expect(sig.type).toEqual({ type: "intrinsic", name: "AuthSession" });
  });

  it("assigns unique integer ids to every node", () => {
    const allIds: number[] = [];
    function collect(decl: TypeDocDeclaration) {
      allIds.push(decl.id);
      for (const child of decl.children ?? []) collect(child);
      for (const sig of decl.signatures ?? []) {
        allIds.push(sig.id);
        for (const param of sig.parameters ?? []) allIds.push(param.id);
      }
    }
    allIds.push(result.id);
    for (const child of result.children) collect(child);
    expect(new Set(allIds).size).toBe(allIds.length);
  });
});

// ---------------------------------------------------------------------------
// Category injection via categoryMap
// ---------------------------------------------------------------------------

describe("transformSymbolGraph with categoryMap", () => {
  const mapped = transformSymbolGraph([fixture], "Auth", { Auth: "Authentication" });

  it("injects @category on a top-level class with an existing doc comment", () => {
    const cls = mapped.children.find(c => c.name === "AuthClient")!;
    const tag = cls.comment?.blockTags?.find(t => t.tag === "@category");
    expect(tag).toBeDefined();
    expect(tag!.content[0].text).toBe("Authentication");
    expect(cls.comment?.summary).toEqual([{ kind: "text", text: "Manages authentication state." }]);
  });

  it("injects @category on a callable member with no prior comment", () => {
    const cls = mapped.children.find(c => c.name === "AuthClient")!;
    const method = cls.children?.find(c => c.name === "signIn")!;
    const tag = method.comment?.blockTags?.find(t => t.tag === "@category");
    expect(tag).toBeDefined();
    expect(tag!.content[0].text).toBe("Authentication");
    expect(method.comment?.summary).toEqual([]);
  });

  it("does not inject @category when module is absent from map", () => {
    const none = transformSymbolGraph([fixture], "Auth", {});
    const cls = none.children.find(c => c.name === "AuthClient")!;
    expect(cls.comment?.blockTags?.find(t => t.tag === "@category")).toBeUndefined();
  });
});
