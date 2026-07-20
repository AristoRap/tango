# Compiler

`compiler/` owns phase orchestration.

It may:

- run phases in order
- retain phase outputs for debugging
- expose a simple library API such as `Tango.compile`

It must not:

- inspect Crystal AST details
- invent facts
- choose optimization strategies
- know command-line flags
- shell out to Go or Crystal toolchains directly

The current spine is:

```text
Crystal semantic result
-> NIR
-> facts
-> plans
-> LIR
-> Go IR
-> Go source
```

When adding phases, wire them here only after their boundary contract is clear.
