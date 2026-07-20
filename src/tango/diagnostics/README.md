# Diagnostics

`diagnostics/` owns diagnostic data contracts.

Every phase should convert native failures or findings into shared diagnostic
data before rendering. CLI text, LSP output, and future machine-readable reports
should consume the same diagnostic structures.

This boundary owns:

- stable diagnostic codes
- origin and severity data
- source location fields
- terminal source-context rendering
- conversions from frontend/emitter errors

Diagnostics should not decide compiler behavior. They describe failures and
findings produced elsewhere.
