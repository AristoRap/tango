# Planning

`planning/` chooses strategies.

Plans answer "what shape should this become?" They consume NIR plus facts and
produce optional execution or representation decisions.

`driver.cr` schedules an explicit, ordered list of strategies over NIR and
facts that each write into a shared `Plans::Table`. Strategies live in
`strategies/`. Currently wired:

```text
layout       -> runtime class/struct layouts
repr         -> pointer vs carrier union representation
arrays       -> array representation
hashes       -> hash representation and ordering
core_dispatch -> equality, type-test, and cast strategies
monomorphize -> concrete def names and block protocols
capabilities -> static specialization for proven concrete capability witnesses
calls        -> resolved internal/external call targets
constructors -> allocation and initializer functions
blocks       -> call-site block protocols
exceptions   -> handler lowering strategy
stringifications -> scalar presentation semantics
semantic_collections -> eager fallback or evidence-backed fused traversal
collection_productions -> collection realization
```

Examples:

- external call shape
- static specialization of a capability-typed argument
- stream fusion for `select.map.sum`
- materialized enumerable chain
- split-field extraction
- allocation shape
- union representation choice
- block invocation protocol

Planning may choose an optimization only when analysis facts prove it is legal.
It should not rediscover those facts by walking source details directly.

Collection operations stay semantic in NIR. Development chooses
`MaterializeViaFallback` for bodyful map/filter/each/fold operations. Release
also materializes Array `select.map.reduce`: fusion would interleave stages and
change exception order until executable-node effect evidence is conservative
and exhaustive. Release may select `FusedCollectionTraversal` only to stream a
planned `String#split` production directly into `each`. Targets never scan the
program graph during emission.

Good discipline:

```text
analysis proves safety
planning chooses strategy
lowering commits strategy into LIR
```

If a plan cannot be justified by facts, either add the missing analysis pass or
choose the conservative plan.
