import { spawnSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import type { SymbolGraph } from "./symbol-graph.js";

export function extractSymbolGraphs(sdkRoot: string): SymbolGraph[] {
  const result = spawnSync(
    "swift",
    ["package", "dump-symbol-graph", "--minimum-access-level", "public"],
    { cwd: sdkRoot, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }
  );

  if (result.error) {
    throw new Error(`Failed to spawn swift: ${result.error.message}`);
  }

  // dump-symbol-graph exits non-zero when test-only targets can't load on the
  // current platform (e.g. iOS test targets on macOS). We tolerate this as long
  // as the primary module symbol graphs were produced.
  const buildDir = join(sdkRoot, ".build");
  const archDir = readdirSync(buildDir).find(
    d => existsSync(join(buildDir, d, "symbolgraph"))
  );

  if (!archDir) {
    // No symbol graphs at all — surface the original error
    throw new Error(`swift package dump-symbol-graph failed:\n${result.stderr}`);
  }

  const symbolgraphDir = join(buildDir, archDir, "symbolgraph");
  const graphs: SymbolGraph[] = [];
  for (const file of readdirSync(symbolgraphDir)) {
    // Skip cross-module extension graphs (e.g. Auth@Foundation.symbols.json)
    if (!file.endsWith(".symbols.json") || file.includes("@")) continue;
    const raw = readFileSync(join(symbolgraphDir, file), "utf8");
    graphs.push(JSON.parse(raw) as SymbolGraph);
  }

  return graphs;
}
