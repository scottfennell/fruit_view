# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root — canonical domain glossary and key architecture decisions
- **`docs/adr/`** — read ADRs that touch the area you are about to work in
- **`README.md`** — current operator-facing runtime contract, including the active viewer-to-vehicle RC packet
- **`vehicle_node/docs/rc-protocol.md`** — canonical wire-level control packet for viewer and vehicle-node integration
- **`docs/vehicle-node-prd.md`** — subsystem boundary and migration notes between viewer semantics and RC channels

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront.

## File structure

Single-context repo:

```
/
├── CONTEXT.md
├── docs/
│   ├── agents/          ← skill configuration (this dir)
│   └── adr/             ← architectural decision records
├── vehicle_node/        ← Raspberry Pi vehicle-node subsystem and protocol docs
├── scripts/
├── scenes/
├── shaders/
├── sidecar/
├── deploy/
└── tests/
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0003 (GStreamer sidecar over GDExtension) — but worth reopening because…_
