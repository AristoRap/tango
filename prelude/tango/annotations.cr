annotation Go
end

annotation GoType
end

# Marks prelude defs that exist only so a Crystal parser-keyword expansion
# type-checks (e.g. `select`). The frontend recognizes the surface keyword and
# never lowers these — they emit nothing.
annotation TangoInternal
end

# Reserved compiler marker for ordinary prelude bodies that also expose a
# target-neutral semantic collection operation. User source may call the
# annotated method, but may not apply this annotation to its own declarations.
annotation TangoSemantic
end
