# Toolchain

`toolchain/` owns external compiler/runtime discovery and execution.

It is the only boundary that should shell out to tools such as `go` or
`crystal env`.

Responsibilities:

- resolve pinned toolchains from environment variables
- discover trusted defaults from PATH
- validate minimum versions
- set repo-local caches
- run or build generated target source
- set up Crystal's source path for the embedded frontend

Normal compiler phases should not call `Process.run` directly.

Security stance: Tango should not download or execute a new toolchain as a side
effect of build/run. Future auto-fetching must be an explicit command.
