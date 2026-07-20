# Go Target

`target/go/` owns Go IR and Go source emission.

Current flow:

```text
LIR -> Go IR + runtime requirements -> Go source
```

`from_lir.cr` maps LIR operations into Go IR. `source.cr` prints Go source.
Neither should know about CLI commands, workspace paths, or how Go is executed.

The Go target may decide syntax-level details such as imports and selectors.
It should not decide whether an enumerable chain is fused, how a union is boxed,
or whether an external call is legal. Those decisions belong earlier.

Fast Go is allowed and desired. The constraint is that performance-sensitive
shapes should arrive from LIR as explicit fundamentals, backed by facts and
plans, so Go emission stays simple without becoming slow by default.

Runtime helpers are demand-driven requirements, not a global prelude dump. See
`runtime/` for the import/helper dependency seam.

Channel iterator steps arrive as `ChanReceiveState`; the target mechanically
spells one comma-ok receive into the committed value/open struct. It does not
interpret nil as closure. Concrete generic structs arrive with distinct safe
names, and an unconditional Tango `while true` is spelled as Go's terminating
`for {}` form.

`FusedCollectionTraversal` arrives with an explicit source, ordered transforms,
and fold terminal. The target binds those values once and spells one typed Go
range loop; it does not decide whether the chain was safe or which profile
requested it.
