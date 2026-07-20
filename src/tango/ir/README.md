# IR

`ir/` owns Tango intermediate representation data structures.

Current layers:

- `NIR`: normalized frontend IR
- `LIR`: lowered IR with explicit runtime/backend-facing operations

NIR should stay close enough to source semantics for analysis and planning.
LIR should be explicit enough that target backends are mostly mechanical.
Bodyful semantic collection operations retain their Crystal-resolved ordinary
Call as fallback data while exposing source/block composition through the NIR
graph; planning, not the node, chooses whether that fallback executes.
Indexed reads and writes use the same retained-call seam: `IndexedRead` and
`IndexedWrite` expose the capability meaning while their ordinary Indexable
bodies remain the conservative lowering oracle.
Channel traversal keeps its comma-ok receive as `ChannelOp::NextState` in NIR
and `ChanReceiveState` in LIR. The state is not a nullable payload: ordinary
Iterator code maps only the closed flag to the distinct stop sentinel.

The first fused collection lowering is one `FusedCollectionTraversal` value
whose `ArrayElements` source, filter/map transforms, and fold terminal remain
independent axes. LIR records that planning already selected one traversal; it
does not carry eligibility policy or reconstruct the semantic graph.

Concrete generic value structs retain their full language type identity in
LIR, while their Go-safe declaration name is already committed. This prevents
different lazy iterator wrapper instantiations from collapsing onto one target
struct.

IR types should be boring data. They should not:

- run analysis
- choose optimizations
- emit source
- inspect toolchains

When behavior starts accumulating on IR nodes, consider whether it belongs in a
pass, planner, lowerer, or target translator instead.
