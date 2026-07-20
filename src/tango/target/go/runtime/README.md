# Go Runtime Requirements

`target/go/runtime/` owns demand-driven Go runtime injection.

This boundary models things the emitted Go file needs beyond user code:

- imports
- helper functions
- helper type declarations
- dependencies between helpers

The seam exists before any non-trivial helpers are added. Today, imports already
flow through runtime requirements; helper snippets are intentionally empty until
lowering introduces a real semantic protocol that needs support code.

Runtime requirements are deduped by key and ordered dependency-first. Source
emission decides where imports and helpers print; lower phases decide what is
required.

Rules:

- Do not inject helpers unconditionally.
- Do not add speculative helpers.
- Do not hide language-level decisions in helper selection.
- Lowering should emit requirements only after facts and plans choose the
  semantic protocol that needs them.
