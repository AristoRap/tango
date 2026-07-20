# Crystal Frontend

`frontend/crystal/` embeds Crystal as the semantic oracle.

`semantic.cr` configures Crystal's compiler library with `no_codegen = true`
and the Tango prelude. `to_nir.cr` translates Crystal's typed AST into Tango
NIR. `syntax_surface_builder.cr` performs the one editor-owned parser pass per
source file and immediately projects it into Crystal-free `SyntaxSurface`
records, including declarations Crystal never semantically instantiates.

The Tango prelude is part of the frontend contract: it gives Crystal enough
bodyless definitions and annotations to typecheck source while preserving the
information Tango needs later.

This boundary may depend on Crystal compiler internals. Other phases should not.

Important rule: once a detail crosses this boundary, it should be expressed in
Tango terms. Downstream phases should not need to know how Crystal happened to
spell it.
