import { defineConfig } from "@supabase/doc-generator";

// What supabase-swift tells the shared generator in supabase/sdk. Paths are relative to this file.
// The options are the `Config` and `SwiftSymbolGraphSource` types in
// https://github.com/supabase/sdk/blob/main/packages/doc-generator/src/config.ts
//
// Every public function, method and initializer gets one definition, documented or not. Its id is
// its name in lowercase words: `AuthClient.signUp` is `auth-client-sign-up`. To leave some out,
// add `exclude`: regular expressions matched against that name.
export default defineConfig({
  source: {
    // Symbol graphs the Swift compiler emits; scripts/api-docs.sh builds them.
    format: "swift-symbol-graph",
    directory: "../../.build/api-docs/symbol-graphs",
    // The build also emits a graph for every dependency. Only these are documented.
    modules: ["Auth", "Functions", "Helpers", "PostgREST", "Realtime", "Storage", "Supabase"],
  },
  output: "../../docs/api-docs/definitions",
  // A public function without a doc comment fails the run, so none can be added undocumented.
  strict: true,
  // Where the docs site shows this SDK: /docs/reference-beta/swift. For `api-docs.sh --preview`.
  preview: { path: "swift", title: "Swift" },
});
