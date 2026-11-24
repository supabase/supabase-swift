# API docs

Generates the API docs definitions that supabase.com/docs reads: one Markdown file for each
public function, method and initializer, with a doc comment or without one, written to
[`docs/api-docs/definitions`](../../docs/api-docs/definitions).

The file name is the `id` of the definition, and it is made from the code alone: the path through
the types to the function, in lowercase words. `AuthClient.signUp(email:password:options:)` is
`auth-client-sign-up`. Overloads share one definition. Renaming a function or its type changes the
id, and with it the address of the page on the docs site.

This folder holds no logic. The generator and the check are the `@supabase/doc-generator` and
`@supabase/doc-check` packages of [supabase/sdk](https://github.com/supabase/sdk), shared by every
SDK. What is specific to supabase-swift is in [`doc-generator.config.mjs`](doc-generator.config.mjs).

> **Prototype.** The two packages are not on npm yet. `package.json` links them from a checkout of
> supabase/sdk next to this repository, on its `feature/doc-generator` branch.

## Setup

Needs git, bun and npm. Run the commands from the root of this repository.

```bash
# 1. Check out supabase/sdk next to this repository, as ../sdk, on the branch with the packages:
git clone --branch feature/doc-generator https://github.com/supabase/sdk.git ../sdk

# 2. Build the two packages there, once and after every change there:
(cd ../sdk/packages/doc-check && bun install && bun run build)
(cd ../sdk/packages/doc-generator && bun install && bun run build)

# 3. Link them into this folder, once:
npm install --prefix tools/api-docs
```

`npm install` fails until steps 1 and 2 are done. To get the newest commit of the branch, run
`git -C ../sdk pull` and step 2 again.

With a checkout of supabase/sdk that you already have, skip the clone:

- **At `../sdk`:** switch it to the branch with `git -C ../sdk switch feature/doc-generator`.
- **Somewhere else:** link it with `ln -s <absolute path of your checkout> ../sdk`.

The checkout is an ordinary one. To work on the two packages, change them there and build them
again.

## Commands

```bash
./scripts/api-docs.sh          # build the symbol graphs, generate, then check
./scripts/api-docs.sh --check  # only check the definitions that are there
```

Generating needs macOS and the Swift toolchain. Checking needs only Node.

### Options

The options of the two tools go through one environment variable each, the same two in every SDK.
The script hands them on as written, split at spaces:

| Variable        | Goes to         | Taken by                                    |
| --------------- | --------------- | ------------------------------------------- |
| `GENERATE_ARGS` | `doc-generator` | Every run that generates: all but `--check` |
| `CHECK_ARGS`    | `doc-check`     | Every run                                   |

```bash
GENERATE_ARGS="--verbose" ./scripts/api-docs.sh
GENERATE_ARGS="--verbose" CHECK_ARGS="--schema-url https://example.com/definition.schema.json" ./scripts/api-docs.sh
```

A tool rejects an option it does not know: it prints its usage and exits with code 2, which stops
the run. The options of each tool are in its README in supabase/sdk:

- `doc-generator`: [Options](https://github.com/supabase/sdk/blob/main/packages/doc-generator/README.md#options) in `packages/doc-generator/README.md`
- `doc-check`: [Which schema](https://github.com/supabase/sdk/blob/main/packages/doc-check/README.md#which-schema) in `packages/doc-check/README.md`

The check uses the schema bundled with `@supabase/doc-check`. To check against the schema the docs
team has now, give it a URL, or a file in Git at a branch or a full commit SHA:

```bash
CHECK_ARGS="--schema-git https://github.com/supabase/supabase.git \
  --schema-ref jeremias/reference-beta \
  --schema-path apps/docs/content/reference-beta/definition.schema.json" \
  ./scripts/api-docs.sh --check

CHECK_ARGS="--schema-url https://example.com/definition.schema.json" ./scripts/api-docs.sh --check
```

## Preview on the docs site

To see the definitions as supabase.com will show them, the preview copies them into a local
checkout of [supabase/supabase](https://github.com/supabase/supabase), starts the docs site there
(`pnpm dev:docs`) and opens the page in your browser. The checkout has to be on a branch that has
the new reference pages. Today that is the docs team's `jeremias/reference-beta`.

```bash
./scripts/api-docs.sh --preview ../supabase   # generate, check, copy, then serve
# Starts the docs site, then opens http://localhost:3001/docs/reference-beta/swift. Ctrl-C stops it.
```

When the docs site already runs, the preview only opens the page. The first start of the docs
site takes a while, and needs `pnpm install` in the checkout first.

The preview replaces the definitions of the preview before. It writes a placeholder introduction
page the first time and never overwrites one, so that page can be edited in the docs checkout.
The docs checkout ignores the copied definitions in Git.

## Editing

The definitions are generated files: change the doc comment, then run the script again. Never
edit them by hand.

Every public function, method and initializer needs a doc comment: the config sets `strict: true`,
so the script fails and lists the ones that have none. It writes nothing until they are fixed.

To leave a function out, documented or not, add `exclude` to
[`doc-generator.config.mjs`](doc-generator.config.mjs): regular expressions matched against names
such as `AuthClient.signUp`. `"\\.init$"` leaves out every initializer.
