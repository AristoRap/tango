# Lowering

`lowering/` commits NIR + facts + plans into LIR.

This is where implicit language behavior becomes explicit compiler operations.

Examples that belong here:

- `if` as value into temporaries
- nilable and union boxing protocols
- rescue protocol
- block break/next/return protocol
- selected allocation shape
- selected collection source/transform/terminal composition
- selected bodyful semantic-call fallback
- selected external-call shape
- closed-aware channel receive state
- concrete generic value-struct declarations

Lowering may use facts and plans, but it should not perform fresh analysis or
invent new strategies. If lowering needs a clever decision, that decision should
already exist as a plan.

Output from this boundary is LIR.
