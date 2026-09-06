/// Who an aura's effects act on. Read from a `RuleDefinition`'s optional
/// `scope` key (`"self"` — the default — or `"opponent"`). It is the only
/// aura-specific metadata `AuraBinder._wire` needs; the
/// rule body itself stays identity-free.
enum AuraScope { self, opponent }
