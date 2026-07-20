# CLI

`cli/` owns the user command surface.

Current commands:

- `tango run [file|-] [--race] [--release]`
- `tango build [file|-] [-o output] [--race] [--release]`
- `tango emit go [--release] [file|-]`
- `tango dump nir [--release] [file|-]`
- `tango dump facts [--release] [file|-]`
- `tango dump plans [--release] [file|-]`
- `tango dump lir [--release] [file|-]`
- `tango fmt [--check] [path ...]`

Normal users should use `run` and `build`. `emit go` and `dump <phase>` are
debugging commands for inspecting the hidden backend output and the intermediate
compiler phases.

`--release` selects evidence-backed Tango planning policy. It does not change
language semantics or map to a Go optimization flag. `emit` and every dump
accept the same profile so a release plan remains inspectable.

`fmt` delegates layout to the in-process Crystal formatter. Explicit files are
formatted regardless of extension; directories and the no-path current-tree
mode discover `.tn` files recursively in stable order. `-` filters stdin to
stdout and must be the only path. `--check` never writes and exits non-zero for
non-canonical or invalid input. Batch mode formats every source in memory before
writing any file, so a missing, invalid-UTF-8, or syntactically broken input
cannot leave an otherwise valid batch partially reformatted.

The CLI may:

- parse argv
- read files or stdin
- choose user-facing command behavior
- call the compiler API
- call the frontend formatting adapter
- call toolchain execution for run/build

It must not:

- inspect IR internals
- run analysis or lowering directly
- know Crystal AST details
- emit target source by hand
