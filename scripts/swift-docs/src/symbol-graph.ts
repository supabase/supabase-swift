export interface DeclarationFragment {
  kind: string;
  spelling: string;
  preciseIdentifier?: string;
}

export interface DocCommentLine {
  range?: {
    start: { line: number; character: number };
    end: { line: number; character: number };
  };
  text: string;
}

export interface FunctionParameter {
  name: string;
  declarationFragments: DeclarationFragment[];
}

export interface SwiftGenericParameter {
  name: string;
  index: number;
  depth: number;
}

export interface SymbolGraphSymbol {
  identifier: { precise: string; interfaceLanguage: string };
  kind: { identifier: string; displayName: string };
  names: { title: string };
  docComment?: { lines: DocCommentLine[] };
  declarationFragments?: DeclarationFragment[];
  functionSignature?: {
    parameters: FunctionParameter[];
    returns: DeclarationFragment[];
  };
  accessLevel: string;
  location?: { uri: string; position: { line: number; character: number } };
  swiftGenerics?: { parameters?: SwiftGenericParameter[] };
}

export interface Relationship {
  kind: string;
  source: string;
  target: string;
  targetFallback?: string;
}

export interface SymbolGraph {
  module: {
    name: string;
    platform: { operatingSystem: { name: string }; architecture: string };
  };
  symbols: SymbolGraphSymbol[];
  relationships: Relationship[];
}
