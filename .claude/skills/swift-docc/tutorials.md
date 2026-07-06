# DocC Tutorial Files

Tutorials use `.tutorial` files (not `.md`) and a separate table-of-contents file.

## Tutorial table-of-contents

Filename: anything ending in `.tutorial`, at the catalog root. Uses `@Tutorials`:

```
@Tutorials(name: "Module Name") {
  @Intro(title: "Tutorial Series Title") {
    One paragraph introducing the tutorial series.
  }
  @Chapter(name: "Chapter 1") {
    @Image(source: "chapter1.png", alt: "Accessible description.")
    @TutorialReference(tutorial: "doc:PageName")
  }
}
```

## Individual tutorial page

Filename: `PageName.tutorial` inside a chapter subfolder:

```
@Tutorial() {
  @Intro(title: "Tutorial Page Title") {
    One paragraph introducing this tutorial page.
  }
  @Section(title: "Section Name") {
    @ContentAndMedia {
      Explanatory text before steps.
      @Image(source: "section-image.png", alt: "Accessible description.")
    }
    @Steps {
      @Step {
        Instruction for this step.
        @Code(name: "DisplayName.swift", file: "step1-complete.swift")
      }
      @Step {
        Next instruction.
        @Image(source: "result.png", alt: "What the user sees after this step.")
      }
    }
  }
}
```

## Catalog layout for tutorials

```
Sources/MyModule/MyModule.docc/
├── MyModule.md                   ← landing page
├── table-of-contents.tutorial    ← tutorial TOC
├── Chapter01/
│   ├── page-01.tutorial
│   └── Resources/
│       └── step1-complete.swift  ← code file referenced by @Code
└── Resources/
    └── chapter1.png
```

## Key rules

- `@Code(name:file:)` — `name` is the tab label shown to the user; `file` is the filename inside the `Resources/` folder of that chapter.
- Each `@Step` should contain exactly one `@Code` or one `@Image`, not both.
- `@Image` alt text is required and must be descriptive (accessibility requirement).
- Tutorial files do not use `///` comments — all content is in the `.tutorial` markup.
