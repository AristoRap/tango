# Tango

**Crystal in. Go out.**

Tango is an experimental compiler that turns a (growing) subset of
[Crystal](https://crystal-lang.org/) into native Go programs. It uses Crystal's
frontend for parsing and semantic analysis, then carries the result through its
own typed, phase-oriented compiler pipeline before handing generated Go to the
Go toolchain.

The goal is to pair Crystal's expressive syntax and type system with Go's
toolchain, deployment model, and concurrency runtime—without reducing the
compiler to a direct AST-to-source translator.

A Tango program can look like this (`hello.tn`):

```crystal
ch = Channel(Int32).new
spawn { ch.send(40 + 2) }
puts ch.receive
```

```console
$ bin/tango run hello.tn
42
```

## Project status

Tango is early-stage software.
It compiles useful programs, but it is not a drop-in Crystal compiler and
should not be treated as production-ready. Unsupported language constructs
(should) fail with source-located diagnostics instead of silently changing behavior.

The implemented surface currently includes:

- functions, classes, structs, enums, blocks, and local `require` graphs;
- control flow, unions, nilable values, and type narrowing;
- strings, arrays, hashes, and core enumerable operations;
- checked integer arithmetic and floating-point arithmetic;
- `spawn`, channels, mutexes, and `select`;
- exceptions with `raise`, `rescue`, `else`, and `ensure`.

The [`examples/`](examples/) directory is the best executable index of what works today.

## Quick start

You will need:

- Crystal 1.20.2 or newer;
- Go 1.21 or newer, including `gofmt`;

Build Tango and check the local toolchains:

```sh
shards build tango
bin/tango doctor
```

Then run an example:

```sh
bin/tango run examples/spawn_channel.tn
```

Tango source conventionally uses the `.tn` extension. The CLI also reads from
standard input when the file is omitted or given as `-`:

```sh
printf 'puts 42\n' | bin/tango run -
```

## Development

Run the same checks used by CI with:

```sh
make ci
```

## Using Tango

Run a program directly:

```sh
bin/tango run app.tn
```

Build a native executable:

```sh
bin/tango build app.tn
bin/tango build app.tn -o tango-app
```

Pass `--race` to `run` or `build` to enable Go's race detector:

```sh
bin/tango run app.tn --race
```

Pass `--release` to select evidence-backed Tango planning policy. Release mode
preserves language semantics and remains visible through `emit go` and every
phase dump:

```sh
bin/tango build app.tn --release
bin/tango dump plans app.tn --release
```

Format Tango source in place, or verify formatting without writing:

```sh
bin/tango fmt app.tn
bin/tango fmt --check app.tn examples/
printf 'puts( 42 )' | bin/tango fmt -
```

With no paths, `tango fmt` recursively formats `.tn` files beneath the current
directory. Formatting uses Crystal's canonical formatter directly; Tango does
not define a second style or read formatter configuration.

The remaining commands expose the compiler and its tooling:

| Command                   | Purpose                                 |
| ------------------------- | --------------------------------------- |
| `tango emit go <file>`    | Print formatted generated Go            |
| `tango dump nir <file>`   | Inspect normalized IR                   |
| `tango dump facts <file>` | Inspect analysis facts                  |
| `tango dump plans <file>` | Inspect planning decisions              |
| `tango dump lir <file>`   | Inspect lowered IR                      |
| `tango fmt [path ...]`    | Format Tango source with Crystal        |
| `tango lsp`               | Start the language server over stdio    |
| `tango doctor`            | Check the Crystal and Go environment    |
| `tango clean`             | Remove Tango's local `.tango` workspace |

`dump nir` and `dump lir` also accept `--trace` for a compact view of the
lowering seam.

## How it works

Tango deliberately separates understanding a program from deciding how to
represent it and spelling it as Go:

```text
Crystal source
    ↓
Crystal frontend (parse, expand, type-check)
    ↓
Normalized IR (NIR)
    ↓
Analysis facts → planning decisions
    ↓
Lowered IR (LIR)
    ↓
Go IR → formatted Go → Go toolchain
```

Analysis proves facts, planning chooses strategies, lowering commits those choices, and the Go target only spells them.

## Editor support

A basic VS Code extension for `.tn` files lives in [`editors/vscode/`](editors/vscode/).
It starts `tango lsp` and provides diagnostics, navigation, hover, and document
formatting through the same formatter used by `tango fmt`.

## License

Tango is available under the [MIT License](LICENSE).
