# Expansion

`expansion/` converts already-resolved Tango NIR calls into richer semantic NIR
when a reserved prelude annotation explicitly authorizes that meaning. The
same seam covers eager collection operations and Indexable's indexed reads and
writes.

Expansion does not resolve names, infer types, choose plans, or inspect target
APIs. Every semantic collection operation retains its complete ordinary Call as
the language-level oracle and conservative lowering fallback. Frontends hand
ordinary resolved calls to `Expansion::Driver`; the core invokes that one
deterministic whole-program phase before analysis, so builds, snapshots, dumps,
and editor analysis all receive the same expanded NIR.
