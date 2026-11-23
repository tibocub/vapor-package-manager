# vpm documentation

Current state and plans first, then the established systems, then history.

| document | what it is |
|---|---|
| [status.md](status.md) | what works today and what is not verified |
| [roadmap.md](roadmap.md) | immediate goals, long-term goals, ideas |
| [spec.md](spec.md) | commands, paths, config, manifest, plan format, exit codes (specification) |
| [dependency-resolution.md](dependency-resolution.md) | versions, the resolver, global versus local rules |
| [state-and-tracking.md](state-and-tracking.md) | on-disk layout, records, who uses what |
| [native-detection.md](native-detection.md) | pure / c / build / other classification and build plans |
| [luarocks-source.md](luarocks-source.md), [index-and-network.md](index-and-network.md), [signing.md](signing.md) | the signed index, transport, trust |
| [publishing.md](publishing.md) | `vpm publish` and the luarocks.org upload API |
| [ram-budget.md](ram-budget.md) | what the RP2040 allows and how vpm stays inside it |
| [design.md](design.md), [pure-lua-filter.md](pure-lua-filter.md), [vaporos-prerequisites.md](vaporos-prerequisites.md), [open-questions.md](open-questions.md), [decisions.md](decisions.md) | the original vaporOS-era design, history and the dated decision log. Parts are superseded (vpm used to offer only pure-Lua rocks and only on vaporOS) |
