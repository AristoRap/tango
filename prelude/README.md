# Tango Prelude

`tango.cr` is the ordered manifest for Tango's implicit language surface.
Keep declarations in the responsibility-shaped files under `tango/`; the
manifest itself contains only relative requires.

The prelude is intentionally smaller in scope than the eventual standard
library. It contains declarations needed by ordinary Tango programs without an
explicit require: bootstrap annotations and macros, fundamental types,
collections, concurrency primitives, exceptions, time, and basic output.
Larger facilities belong in bundled, explicitly required Tango packages rather
than this implicit surface. Filesystem access begins that layer at
`require "tango/fs"`; JSON and HTTP remain future packages.

The loading model has four layers:

1. the always-implicit bootstrap prelude for compiler and syntax plumbing;
2. the implicit core library for universally expected language facilities;
3. bundled standard packages loaded by explicit Tango `require`s; and
4. future external packages.

Bootstrap and core are distinct ownership categories but currently enter
Crystal semantics through this same manifest. `time.cr` currently owns only the
small top-level numeric `sleep` operation; richer `Time` types and APIs belong
in an explicitly required bundled package.

A public method's contract is always Tango-owned. Implement it with the
smallest suitable mechanism:

1. an ordinary Tango body when existing operations can express it;
2. a direct `@[Go]` binding when the target operation has the same contract;
3. a private runtime adapter when target semantics need repair; or
4. a compiler primitive when representation or control flow requires a full
   phase-chain slice.

Splitting files here is an ownership and navigation boundary. It does not make
their contents selectively loaded: every file required by `tango.cr` remains
part of Crystal's semantic input, so keep the implicit surface lean.

`Comparable(T)` derives the conventional ordering operators from one required
`<=>` method. The eight supported integers and String provide total-order
results; Float64 returns `Int32?` because any comparison involving NaN is
unordered. Concrete scalar operators may remain primitive leaves without
changing the shared language capability or introducing target interfaces.
Comparable reference equality preserves Crystal's identical-object fast path
before consulting a potentially partial `<=>`.

The supported scalar universe is the eight integer widths plus `Float64`.
Integers provide homogeneous checked/wrapping arithmetic and power, true
division through `Float64`, and explicit mixed Float64 operations. Float64
provides IEEE arithmetic, classification, sign-preserving unary operations,
rounding, adjacent values, power, and checked conversion to every supported
integer. Float32, 128-bit integers, and the broader `Math` library are outside
the implicit core surface.

`Enumerable(T)` is eager and materializing. `Iterator(T)` is the separate
stateful, one-shot capability: `next` returns either an element or the distinct
`Iterator::Stop`, and its map/select/reject wrappers consume lazily. Channel
implements that contract through a private closed-aware state leaf so nullable
channel data never doubles as the stop signal.

`Indexable(T)` and `MutableIndexable(T)` provide the shared indexed collection
contract. Concrete types implement only stable `size` plus unchecked
`unsafe_fetch`/`unsafe_put`; public `[]`, `[]=`, and `each` normalize negative
indices and derive traversal through those leaves. Invalid normalized indices
retain non-rescuable Go runtime-fault behavior.
