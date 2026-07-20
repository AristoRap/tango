# Targets

`target/` contains backend-specific translation and source emission.

Targets consume LIR and produce target IR/source. They should be policy-thin:
target-native and efficient, but not responsible for proving or choosing
language-level strategies.

Targets may:

- translate LIR into target IR
- print target source
- own target syntax details
- own target import spelling

Targets must not:

- inspect Crystal AST
- choose language-level optimization strategies
- decide runtime representations
- manage generated artifact paths
- invoke external compilers

If backend translation needs a clever decision, move that decision to analysis,
planning, or lowering.

The goal is not naive one-to-one output. The goal is that lowerings converge on
a restricted set of reusable fundamentals, then each target spells those
fundamentals well.
