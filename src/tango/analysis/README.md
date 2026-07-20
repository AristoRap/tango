# Analysis

`analysis/` produces facts.

Facts answer "what is true?" They do not choose how code should be emitted.

`driver.cr` schedules an explicit, ordered list of passes over NIR that each
write into a shared `Facts::Table`. Passes live in `passes/`. Currently
wired:

```text
types         -> expression and aggregate types
annotations   -> resolved Go external bindings
calls         -> concrete call-to-def edges
capabilities  -> Crystal-proven concrete-to-capability conformances
layout        -> class fields, reference/value identity, exception ancestry
comparability -> native equality legality
core_dispatch -> source/target type relations
references    -> lexical declaration edges
blocks        -> capture identities and escape facts
collection_uses -> direct/aliased semantic consumers
collection_legality -> intermediate escape, block effects/raises/control flow,
                       order, replayability, finiteness, cardinality bounds
traversals     -> blocking, destructive consumption, one-shot behavior, and
                  conservative order/finiteness for structured next steps
```

Collection legality is deliberately descriptive. Analysis records individual
laws and observations, including unknowns; it never collapses them into a
`fusible` verdict. Planning remains responsible for choosing a strategy. The
first Release fusion consumes these independent laws for one direct Array
`select.map.reduce` case; every unproven chain continues through the retained
Tango body.
Iterator ancestry is likewise not evidence for Array laws. Channel's structured
closed-aware step records `MayBlock`, `Destructive`, and `OneShot`, while its
finiteness and encounter order remain unknown.

Each pass should own a narrow question and write to a shared fact table. Some
passes can be a single visitor. Others may eventually need fixed-point
iteration.

Examples of facts:

- this call resolves to these annotated targets
- this concrete typed def satisfies this named language capability
- this block captures these locals
- this allocation escapes
- this type has this runtime representation
- this expression is an enumerable chain

Analysis must not emit target code or pick optimization shapes. That belongs in
planning.
