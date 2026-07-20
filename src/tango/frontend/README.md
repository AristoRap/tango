# Frontend

`frontend/` converts an external source-language view into Tango IR.

This is where source-language weirdness is normalized before the rest of the
compiler sees it. For the Crystal frontend, that includes things like macro
expansion artifacts, synthetic constructors, block shapes, `select` lowering
quirks, and other typed-AST details that should not leak downstream.

It may:

- invoke a source frontend
- walk source frontend ASTs
- preserve source spans, type names, target defs, and annotations
- construct NIR

It must not:

- choose runtime representations
- perform optimizations
- emit target code
- shell out to target toolchains

Output from this boundary should be Tango-owned NIR or a deliberately
descriptive frontend projection. `SyntaxSurface` is the editor projection: it
may preserve declarations, documentation, lexical scopes, and explicitly
written types, but never inferred types or resolved identity.

For resolved ordinary calls, the adapter hands the completed target-neutral
Call to `expansion/semantic_calls`; it does not interpret reserved semantic
annotations itself.
