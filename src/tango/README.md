# Tango Source Boundaries

This directory is organized by compiler responsibility, not by helper type.

```text
cli          terminal/user command surface
compiler     phase orchestration
frontend     source language ingestion and normalization
ir           Tango-owned intermediate representations
analysis     fact-producing passes
planning     strategy and optimization selection
lowering     commitment from NIR + facts + plans into explicit LIR
target       backend IR/source emission
toolchain    external compiler/runtime execution
workspace    generated artifact paths and cache layout
diagnostics  shared diagnostic data and rendering contracts
```

The rule of thumb:

```text
facts answer "what is true?"
plans answer "what shape should this become?"
lowering answers "what explicit operations represent that shape?"
targets answer "how does this target spell those operations efficiently?"
```

Target emission should be policy-thin, not necessarily naive. If a target needs
to make a language-level decision, a phase is missing. If a target is spelling an
already-lowered fast shape in the target's natural form, that is the point.
