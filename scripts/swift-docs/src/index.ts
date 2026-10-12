import { resolve } from "node:path";
import { readFileSync, writeFileSync } from "node:fs";
import { extractSymbolGraphs } from "./extract.js";
import { transformSymbolGraph } from "./transform.js";

const sdkRoot = process.argv[2];
const outputPath = process.argv[3] ?? "typedoc.json";
const categoriesPath = process.argv[4];

if (!sdkRoot) {
  console.error("Usage: tsx src/index.ts <sdk-root> [output.json] [categories.json]");
  process.exit(1);
}

const root = resolve(sdkRoot);
const out = resolve(outputPath);

let categoryMap: Record<string, string> = {};
if (categoriesPath) {
  const resolved = resolve(categoriesPath);
  categoryMap = JSON.parse(readFileSync(resolved, "utf8")) as Record<string, string>;
  console.error(`Loaded ${Object.keys(categoryMap).length} category mapping(s) from ${resolved}.`);
}

console.error(`Extracting symbol graphs from ${root}...`);
const graphs = extractSymbolGraphs(root);
console.error(`Found ${graphs.length} symbol graph(s).`);

// Use the umbrella module name if present; otherwise the first graph's name.
const umbrella = graphs.find(g => g.module.name === "Supabase") ?? graphs[0];
const moduleName = umbrella?.module.name ?? "Module";
const project = transformSymbolGraph(graphs, moduleName, categoryMap);

writeFileSync(out, JSON.stringify(project, null, 2), "utf8");
console.error(`Written to ${out}`);
