# Workspace

`workspace/` owns local artifact layout.

It decides where generated files, caches, and default build outputs live. Other
boundaries ask this module for paths instead of reconstructing path policy.

Current policy:

```text
.tango/<source-stem>/main.go
.tango/cache/go-build
.tango/cache/go-mod
```

This boundary may know about repository layout and generated artifact layout.
It should not compile, analyze, plan, lower, emit, or run external tools.
