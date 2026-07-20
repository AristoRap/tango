# Tango Standard Packages

This tree is the only resolver root for bundled `tango/*` packages. Package
files are Tango source, remain definitions-only, and pass through the same
frontend, analysis, planning, lowering, target, snapshot, dump, and editor
pipeline as application source.

The resolver never falls back to Crystal's standard library, `CRYSTAL_PATH`,
or the process working directory for a bare request. `tango/fs` is the first
package; larger filesystem APIs, JSON, HTTP, and richer time APIs grow here only
when an application slice forces them.
