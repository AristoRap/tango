# Source Layout

`src/` contains the Tango implementation. The public shard entrypoint is
`src/tango.cr`; everything else lives under `src/tango/` by boundary.

The compiler shape is intentionally phase-oriented:

```text
source
-> frontend
-> IR
-> analysis facts
-> planning decisions
-> lowered IR
-> target IR
-> source/toolchain
```

Normal users should interact with `tango run` and `tango build`. Target source
emission, such as `tango emit go`, is a debugging surface.
