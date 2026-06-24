export type TypeDocKind =
  | 1 | 8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024 | 2048 | 4096 | 32768 | 131072 | 2097152;

export const KIND_STRING: Record<TypeDocKind, string> = {
  1: "Project", 8: "Enum", 16: "EnumMember", 32: "Variable",
  64: "Function", 128: "Class", 256: "Interface", 512: "Constructor",
  1024: "Property", 2048: "Method", 4096: "Call signature",
  32768: "Parameter", 131072: "Type parameter", 2097152: "Type alias",
};

export interface CommentContent { kind: "text" | "code"; text: string }

export interface CommentBlockTag {
  tag: string;
  name?: string;
  content: CommentContent[];
}

export interface TypeDocComment {
  summary: CommentContent[];
  blockTags?: CommentBlockTag[];
}

export interface TypeDocType {
  type: "intrinsic" | "reference" | "array" | "union" | "typeParameter";
  name?: string;
  elementType?: TypeDocType;
  types?: TypeDocType[];
  typeArguments?: TypeDocType[];
}

export interface TypeDocSource {
  fileName: string;
  line: number;
  character: number;
}

export interface TypeDocTypeParameter {
  id: number;
  name: string;
  kind: 131072;
  kindString: "Type parameter";
  flags: Record<string, never>;
}

export interface TypeDocParameter {
  id: number;
  name: string;
  kind: 32768;
  kindString: "Parameter";
  flags: Record<string, never>;
  comment?: TypeDocComment;
  type?: TypeDocType;
}

export interface TypeDocSignature {
  id: number;
  name: string;
  kind: 4096;
  kindString: "Call signature";
  flags: Record<string, never>;
  comment?: TypeDocComment;
  parameters?: TypeDocParameter[];
  type?: TypeDocType;
  typeParameter?: TypeDocTypeParameter[];
}

export interface TypeDocDeclaration {
  id: number;
  name: string;
  kind: TypeDocKind;
  kindString: string;
  flags: Record<string, unknown>;
  comment?: TypeDocComment;
  sources?: TypeDocSource[];
  children?: TypeDocDeclaration[];
  signatures?: TypeDocSignature[];
  type?: TypeDocType;
  extendedTypes?: TypeDocType[];
  implementedTypes?: TypeDocType[];
  typeParameter?: TypeDocTypeParameter[];
}

export interface TypeDocProject {
  id: 0;
  name: string;
  kind: 1;
  kindString: "Project";
  flags: Record<string, never>;
  children: TypeDocDeclaration[];
}
