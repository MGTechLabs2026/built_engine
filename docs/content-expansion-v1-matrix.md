# Tome: Martial Arts — Content Expansion V1 · Content Matrix

Status: **PROPOSED — review before implementation.**
Scope confirmed: both repos, lean V1, phased commits.
Rule: additive only. No existing id renamed or removed. Existing balance untouched
except where a starter item gains a combine chain (additive fields on its def).

Review this doc for: duplication · missing archetypes · overpowered combinations ·
style imbalance · physique imbalance. Nothing below is written as code yet.

---

## 0. Dimensions & vocabulary (unchanged — reused as-is)

Training dimensions (engine `TrainingDimensions`): `speed`, `power`, `precision`,
`reaction`, `control`, `consistency`.

Evolution tiers (engine `EvolutionTiers`, all four already defined): `basic` <
`intermediate` < `advanced` < `master`.

Styles (6, unchanged): western — `polearming` (reach/control/spacing),
`wrestling` (guard/grab/throw/counter/endurance), `fencing`
(thrust/riposte/speed/initiative); eastern — `shaolin` (palm/power/discipline),
`taiChi` (redirection/flow/reaction/control), `kunlun` (quick blade/evasion/burst).

Physiques (4, unchanged): `sturdy` (defense), `power` (strength), `burst` (speed),
`endurance` (stamina). Tradition lean unchanged: sturdy/power favour western,
burst/endurance favour eastern (±25% / −15% on the physique's one stat).

New tag namespaces this milestone introduces (data only, no new engine mechanic):

| Tag | Meaning | Read by |
|---|---|---|
| `aff:burst` `aff:power` `aff:sturdy` `aff:endurance` | physique affinity of a content piece | client reward weighter |
| `rarity:common` `…:uncommon` `…:rare` `…:master` | discovery rarity | client reward weighter, master-lock gate |
| `stance:sprawl` `stance:en_garde` `stance:swallow` | new style stances (mirror `stance:iron_body` etc.) | new style-affinity modifiers |

---

## C. Technique evolution trees

### C.1 Deepen the three existing families to `master`

Existing forms in **bold-italic** are unchanged; only new `evolution` entries are
appended to the named intermediate forms, and new forms are added.

```
PUNCH  (fist)                                          dominant dim
  basic_punch [basic]
    ├─ light_punch  [intermediate, precision]  ...unchanged 4-way branch
    │    └─▶ precise_jab      [advanced,  precision]   precision
    │          └─▶ lightning_jab   [master, precision+speed]
    ├─ heavy_punch  [intermediate, power]
    │    └─▶ hammer_blow      [advanced,  power]       power
    │          └─▶ mountain_breaker[master, power]
    ├─ fast_punch   [intermediate, speed]
    │    └─▶ flash_strike     [advanced,  speed]       speed
    │          └─▶ thunder_flash  [master, speed+reaction]
    └─ counter_punch[intermediate, reaction]           (stays terminal in V1 —
                                                        reaction line deepened
                                                        under GUARD instead)

SLASH  (blade)
  basic_slash [basic]
    ├─ quick_slash  [intermediate, speed]
    │    └─▶ flashing_slash   [advanced, speed]        speed
    │          └─▶ lightning_slash [master, speed+precision]
    └─ heavy_slash  [intermediate, power]
         └─▶ cleaving_slash   [advanced, power]        power
               └─▶ mountain_cleave [master, power]

GUARD  (guard)
  basic_guard [basic]
    ├─ fast_guard   [intermediate, speed]
    │    └─▶ rolling_guard    [advanced, reaction]     reaction
    └─ counter_guard[intermediate, reaction]
         └─▶ turning_guard    [advanced, reaction+control]
               └─▶ still_water_guard [master, control] (Tai Chi–flavoured)
```

New forms here: 11 (`precise_jab`, `lightning_jab`, `hammer_blow`,
`mountain_breaker`, `flash_strike`, `thunder_flash`, `flashing_slash`,
`lightning_slash`, `cleaving_slash`, `mountain_cleave`, `rolling_guard`,
`turning_guard`, `still_water_guard`) — 13 actually; count reconciled in the
implementation commit.

### C.2 Three new foundational families

```
PALM  (palm)  — eastern lean (shaolin / taiChi), physique aff: power, endurance
  basic_palm [basic]   training {power .3, control .3, precision .2, reaction .2}
    ├─ focused_palm  [intermediate, precision]   {precision .6, control .4}
    │    └─▶ iron_palm      [advanced, power]     {power .6, control .4}
    │          └─▶ thunder_palm  [master, power+precision]
    └─ pushing_palm  [intermediate, control]     {control .6, reaction .4}
         └─▶ still_palm      [advanced, control]  (redirection; taiChi aff)

FINGER  (finger)  — eastern lean (kunlun), physique aff: burst
  basic_finger [basic]  training {precision .4, speed .3, reaction .3}
    ├─ finger_strike [intermediate, precision]   {precision .6, speed .4}
    │    └─▶ piercing_finger[advanced, precision] {precision .7, speed .3}
    │          └─▶ lightning_finger [master, precision+speed]
    └─ needle_finger [intermediate, speed]       {speed .6, reaction .4}

KICK  (kick)  — western lean (polearming reach) + burst, physique aff: burst, power
  basic_kick [basic]   training {power .3, reaction .3, speed .2, control .2}
    ├─ snap_kick     [intermediate, speed]       {speed .6, reaction .4}
    │    └─▶ spinning_kick  [advanced, power]     {power .6, control .4}
    │          └─▶ whirlwind_kick [master, power+reaction]
    └─ thrust_kick   [intermediate, power]       {power .5, control .3, precision .2}
         └─▶ crescent_kick   [advanced, reaction] (counter-on-approach; reach)
```

New forms here: 15. **Family total after V1: punch/slash/guard/palm/finger/kick
= 6 families, ~37 forms** (trimmed to ~32 in implementation by dropping
`needle_finger` / `crescent_kick` if the matrix review wants leaner).

These 3 new base techniques (`basic_palm`, `basic_finger`, `basic_kick`) get a
LEARNING axis (added to `TechniqueIds.bases`) so they must be learned before use,
exactly like the current three. Every evolved form gets a mastery axis for free
(engine already loops all technique defs).

### C.3 Style-technique sets for the three empty styles

`martial_arts` plugin content — style-gated, flat (no evolution), mirroring the
existing polearming / shaolin / taiChi triads. Fills the gap that wrestling,
fencing, kunlun currently have **zero** techniques.

```
WRESTLING (western)         resource: momentum
  collar_tie     opener, {momentum +8},  damage 5  stat 'grapple'
  takedown       {momentum -20, req momentum>19},  damage 17 stat 'grapple'
  sprawl_stance  {addTag stance:sprawl, momentum +5}   (counter stance)

FENCING (western)           resource: momentum
  lunge          opener, {momentum +8},  damage 6  stat 'thrust'
  riposte        {momentum -16, req momentum>15},  damage 14 stat 'thrust'
  en_garde_stance{addTag stance:en_garde, momentum +5} (initiative stance)

KUNLUN (eastern)            resource: qi
  crescent_slash opener, {qi -3, req qi>2},  damage 8  stat 'blade'
  moonfall_slash {qi -8,  req qi>7},         damage 15 stat 'blade'
  swallow_step   {qi -3,  addTag stance:swallow}       (evasive stance)
```

New martial techniques: 9. `martial_arts` plugin goes 6 → 15.

---

## D. Item evolution trees

Template (unchanged mechanic): base `maxClass 3` → 2 grade-2 branches weighted by
`TrainingDimensions` tags → each grade-2 `maxClass 6` → 1 grade-3 masterwork
`maxClass 9`. Reachable only via `combineItems`; only the base is ever placed as
loot.

### D.1 New combinable base: `hand_wraps` (fist, eastern/shaolin, palm & finger builds)

```
hand_wraps      {attack 1}  training {control .4, precision .3, power .3}   aff:endurance
  ├─ focus_wraps    [precision]  {attack 2}  → masters_wraps     {attack 3}
  └─ weighted_wraps [power]      {attack 2}  → diamond_wraps     {attack 4}
```

### D.2 Add combine chains to two starter items (additive `maxClass`/`gradeEvolution`)

Starter ids unchanged; they simply gain a progression path (they stay immediately
usable, `minimum 0`). This is the "starter kits are not mandatory forever" goal.

```
polearm  (reach)   training {power .4, precision .3, control .3}   aff:sturdy
  ├─ reach_spear   [control]  {attack 4}  → sentinel_spear   {attack 6}
  └─ war_glaive    [power]    {attack 4}  → vanguard_glaive  {attack 7}

rapier   (thrust)  training {speed .4, precision .4, reaction .2}  aff:burst
  ├─ duelists_rapier [precision] {attack 4} → masters_rapier  {attack 6}
  └─ swift_rapier    [speed]     {attack 4} → wind_rapier     {attack 6}
```

New item forms: `hand_wraps` chain (5) + `polearm` chain (4) + `rapier` chain (4)
= **13 forms, ~matching the ~14 lean target.** No new armor/footwear family in V1
(deferred — see section L).

---

## E. Style affinity matrix

One signature conditional `Modifier` registered per style in `learnStyle`,
gated on that style's stance tag — the exact pattern Shaolin already uses
(`+4 palm while stance:iron_body`). Non-exclusive: only active in-stance,
never a hard lock on any technique or item.

| Style | Signature affinity modifier (V1) | Gate |
|---|---|---|
| polearming | `+3 add` to `thrust` and `punch` | while `momentum > 15` |
| wrestling | `×1.15` `defense` | while `stance:sprawl` |
| fencing | `+2 add` `initiative` | while `stance:en_garde` |
| shaolin | `+4 add` `palm` *(exists — unchanged)* | while `stance:iron_body` |
| taiChi | `+3 add` `internal` *(new)* | while `stance:tai_chi` |
| kunlun | `+2 add` `speed` *(new)* | while `stance:swallow` |

### E.1 Style specialties — 1–2 per style, unique vs. every other style

Each specialty is engine **content data** (a `spec:<name>` tag granted by
`learnStyle`, plus modifier-engine-expressible parts registered there). The parts
that only manifest during a fight are read by the client `CombatAdapter` off the
character's `spec:*` tags — the same way it already reads live mastery levels and
armour. No `if styleId == …` anywhere: `CombatAdapter` branches on the generic
`spec:*` tag, so any future style that grants the same tag inherits the behaviour.

| Style | Specialty 1 | Specialty 2 | Hard-counters |
|---|---|---|---|
| **polearming** | **Opening Reach** — strikes first on turn 1 of every fight, ignoring initiative | **Spacing** — `reach`-tagged techniques `+3` damage while still unhit this fight | Reach Fighter, squishy rushers |
| **wrestling** | **Clinch** — `grapple`-tagged actions ignore enemy `dodge` and roll success at `+15%` | **Absorb** — taking a hit while `stance:sprawl` grants `+6 momentum` | Evasive Fighter, Flash Duelist |
| **fencing** | **First Blood** — unconditional `+3 initiative`; acts first every round vs. anything without a reach pre-empt | **Riposte Window** — the turn after an enemy action fails, the fencer's next landed hit deals `×2` | Counter Fighter, Counter Master |
| **shaolin** | **Iron Body** — `+4 palm` while `stance:iron_body` *(exists)* | **Conditioning** — `−1` to every incoming hit (floor 1), always on | Fast Striker, multi-hit |
| **taiChi** | **Redirection** — while `stance:tai_chi`, `25%` of damage taken (cap 8) reflects to the attacker | **Flow** — `internal`-tagged techniques never miss | Heavy Brute, The Iron Wall |
| **kunlun** | **Swallow Step** — while `stance:swallow`, the first enemy attack each round is auto-dodged | **Burst Chain** — each consecutive landed `blade` hit `+2` damage; resets on a miss or the enemy's turn | Armor Fighter (with precision), skill ceiling |

Every style now owns a distinct answer to at least one enemy archetype, and no two
specialties share a mechanic (pre-emption / dodge-ignore / initiative / flat
mitigation / reflect / streak are all different levers).

### E.2 Off-specialty penalty — using content outside your style's lane

The affinity matrix (§E) is a soft reward nudge. This is the hard, in-combat
counterpart: a technique or item whose **weapon/technique family** falls outside
the acting style's aligned set deals `×0.85` damage (−15%, mirroring the physique
off-lean). A Shaolin practitioner swinging a `blade` broadsword technique lands it
at −15% vs. a Fencer or Kunlun stylist doing the same.

Aligned families per style (anything with a recognised family tag **not** listed
is penalised; generic/no-family content is neutral, never penalised):

| Style | Aligned families (no penalty) |
|---|---|
| polearming | `reach` `polearm` `thrust` `staff` `kick` `guard` `fist` |
| wrestling | `grapple` `guard` `fist` `improvised` `cloth` |
| fencing | `blade` `thrust` `fist` `finger` |
| shaolin | `palm` `fist` `staff` `kick` |
| taiChi | `internal` `palm` `guard` `fan` |
| kunlun | `blade` `finger` `thrust` `fist` |

Recognised family tags: `fist` `palm` `finger` `blade` `reach` `polearm` `thrust`
`staff` `fan` `grapple` `internal` `guard` `kick` `improvised` `cloth`.

**Where it lives.** Engine exports `styleAlignedFamilies` + `recognisedFamilyTags`
+ `offSpecialtyDamageFactor` (one source of truth, in `martial_vocabulary.dart`).
The client `CombatAdapter` applies the `×0.85` in its own damage calc by reading
that map — a generic branch on "family tag ∈ aligned set?", no `if styleId == …`.
V1 does **not** register per-family `multiply 0.85` modifiers in `learnStyle` (too
many `damageStat` assumptions across the two technique systems); the headless
`runGame` sim honours styles only through `learnStyle`'s clean static modifiers
(the §E table) for now. Wiring the penalty into the headless sim is deferred (§L).

Design intent: a style can still *use* anything (hybrid builds stay legal — spec's
hybrid guardrail), it just isn't as good at it, so committing to your lane is
rewarded without off-lane being locked out.

Content-level affinity (which techniques/items a style's players gravitate to)
is expressed by **existing tags** (`fist`/`blade`/`palm`/`reach`/`thrust`/…),
consumed by the reward weighter (section I), never by a hard requirement.

Style × technique-family affinity (reward weighting, not a lock):

```
              punch palm finger slash guard kick  wrestling-set fencing-set kunlun-set
polearming     ·    ·     ·      ·     +     ++    ·             ·           ·
wrestling      +    ·     ·      ·     ++    +     +++           ·           ·
fencing        ++   ·     +      ++    +     ·     ·             +++         ·
shaolin        +    +++   +      ·     +     ++    ·             ·           ·
taiChi         ·    ++    ·      ·     +++   ·     ·             ·           ·
kunlun         +    ·     +++    ++    ·     +     ·             ·           +++
```

No column is empty; no style shares an identical row.

---

## F. Physique affinity matrix

Physique keeps its current tradition-macro modifier (±25% / −15%). New content
carries **one** `aff:<physique>` tag, consumed only by the reward weighter.

| Physique | Content it is nudged toward (`aff:` tag on the piece) |
|---|---|
| sturdy | guard/counter techniques, `polearm`→sentinel line, armor, `control`/`consistency` items |
| burst | finger family, `fast_*`/`flash_*`/`lightning_*`, `rapier`→swift/wind, `speed`/`reaction` items |
| power | heavy/hammer/mountain lines, `iron_palm`/`thunder_palm`, `war_glaive`, `power` items |
| endurance | palm family, `hand_wraps` line, `consistency` armor, stance techniques |

Style × physique (conceptual, unchanged — restated for the review):

```
             WESTERN                     EASTERN
          Pole  Wrest  Fenc          Shao  TaiChi  Kunlun
sturdy    ++    +++    +             +     ++      +
burst     +     +      +++           ++    +       +++
power     +++   ++     +             +++   +       +
endurance +     ++     +             +     +++     ++
```

`Burst + Wrestling`, `Power + TaiChi`, `Sturdy + Kunlun` stay viable-but-unusual —
they get weaker reward nudges, never a block.

---

## G. Enemy archetypes (8)

Engine `enemy_content.dart` keeps its `{health, damage, damageStat, initiative}`
shape and gains an `archetype` tag + optional fields (`armour`, `dodge`,
`missPunish`, `regen`, `hits`). The **client** `_enemyFor` is rebuilt from a
hardcoded stat ramp into a data table keyed by archetype; `CombatAdapter`
already has `_armourChance` and per-action success rolls to hang the new
behaviours on.

| # | Archetype | Shape | Tests / build question |
|---|---|---|---|
| 1 | Heavy Brute | high HP, high single hit, low init | can you survive a big hit; sustained output |
| 2 | Fast Striker | low HP, high init, `hits: 2` small | defense vs. burst; end it before stacks pile |
| 3 | Guard Specialist | mid HP, `armour` high vs. your hits | armour-break / power, or precision+mastery |
| 4 | Counter Fighter | `missPunish` bonus dmg when your action fails | accuracy; don't over-swing low-% actions |
| 5 | Reach Fighter | always acts first (`initiative` very high) | initiative items / closing speed |
| 6 | Evasive Fighter | `dodge` lowers your hit chance | precision & consistency, not raw power |
| 7 | Armor Fighter | very high `armour` + HP, low damage | raw damage output; patience; DoT-style multi-hit |
| 8 | Endurance Fighter | `regen` each turn, moderate | burst / win the DPS race before it out-heals |

Normal-bout weighting by run number (spec's complexity curve):

```
runs  1–10 : brute, fast_striker            (teach: survive a hit / stop a rush)
runs 11–20 : + guard_specialist, counter_fighter, reach_fighter
runs 21–30 : + evasive_fighter, armor_fighter
runs 31+   : + endurance_fighter, all weighted
```

## H. Boss archetypes (3) — the hard fight each run

| Boss | Shape | Two+ viable counters |
|---|---|---|
| The Iron Wall | huge `armour` + HP, low damage | (a) power/armour-break build; (b) precision build stacking mastery-driven hit% for consistent chip |
| The Flash Duelist | very high init, `dodge`, `hits: 2` | (a) high consistency/precision to land through dodge; (b) out-armour it and trade |
| The Counter Master | heavy `missPunish`, moderate stats | (a) patient high-accuracy build, only high-% actions; (b) overwhelming multi-hit that accepts the trades |

Hard-fight boss selection: weighted by run number so all three cycle in; none
gates on a single build.

---

## I. Reward-pool changes (client)

`RewardAdapter._rollNext` uniform pick → **weighted** pick:

```
weight(candidate) =
    base[rarity]                     common 100 · uncommon 45 · rare 18 · master 6
  × (style tag matches style row?    ×2.0 for ++/+++, ×1.4 for +)
  × (aff:<physique> matches?         ×1.5)
  × (fills a build gap?              ×2.0  — no offensive comp hung / no armor / no technique)
  ÷ (already discovered AND owned?   ÷2.5  — favour "I didn't know this existed")
master forms: weight 0 until run ≥ 8  (deliberately locked; see L)
```

Pool growth — add the new **base** ids only (evolved/grade forms stay
training/combine-only, matching current design):

```
kRewardItemPool      += hand_wraps, polearm, rapier          (starters now lootable
                        as combine seeds; keeps existing 5)
kRewardTechniquePool += basic_palm, basic_finger, basic_kick
```

Engine reward helpers (`RewardResolver`/`RewardDefinition`) are untouched — the
weighting lives in the client adapter that actually renders loot.

---

## J. Content validation

New engine test `test/content/content_expansion_audit_test.dart` (and a runnable
`tool/validate_content.dart` sharing the same checks):

1. every content id (items + techniques + martial + physique + enemy) globally unique
2. every `evolution[].targetId` and `gradeEvolution[].targetId` resolves to a defined id
3. evolution graph is acyclic (DAG)
4. child tier strictly greater than parent tier (`basic<intermediate<advanced<master`)
5. every `training` map key ∈ `TrainingDimensions` constants
6. every `style:<id>` condition references one of the six `MartialStyles`
7. every `aff:<x>` tag ∈ {burst, power, sturdy, endurance}; every `rarity:<x>` ∈ the four
8. every base technique with a LEARNING axis is listed in `TechniqueIds.bases` and vice versa

Client test `test/core/engine/reward_pool_ids_test.dart`: every id in
`kRewardItemPool` / `kRewardTechniquePool` resolves in the engine content registry.

---

## K. Balance risks flagged in advance

- **Master-tier stat creep.** `mountain_breaker` / `thunder_flash` / `lightning_*`
  must stay *sidegrades with a cost* (higher variance, resource-hungry, or
  single-dimension) not flat +damage over their advanced parent. Each master form
  gets a written tradeoff in its def comment.
- **`still_water_guard`** (master control guard) risks being universally best —
  cap its `defense` at parity with `bastion_cloth_armor` and make its value the
  control synergy, not the number.
- **Starter combine chains** (`polearm`, `rapier`) slightly raise western starter
  ceilings — acceptable, they still cost upgrade points and RNG, and eastern gets
  `hand_wraps` as the counterpart.
- **Reward gap-weighting ×2.0** could feel deterministic if the player has an
  obvious hole; keep it a nudge (multiplicative on weight, not a guarantee) and
  never let it push a single candidate above ~55% of the roll.
- **Kunlun** now has both a martial set *and* the strongest finger/blade reward
  nudges — watch that it isn't the strictly-best eastern style; taiChi's `+3
  internal` and shaolin's palm line must keep pace in playtest.
- **Counter Fighter + Counter Master** both punish misses — if the player's
  success rolls are already mastery-gated low early, these could feel unfair on
  runs 11–20. Tune `missPunish` low (≈ +40% of a normal hit) and revisit. Fencing's
  **Riposte Window** is the designed answer — verify it actually swings the matchup.
- **Style specialties stacking with archetypes.** Wrestling **Clinch** vs. Evasive
  Fighter, taiChi **Redirection** vs. The Iron Wall, fencing **Riposte** vs. Counter
  Master are all intended hard counters — confirm in playtest they trivialise the
  fight (good, that's the point) without trivialising the whole run.
- **taiChi Redirection cap.** Uncapped reflect scales with boss damage and could
  solo The Iron Wall; hard-capped at 8/hit and only while `stance:tai_chi` (costs a
  turn and qi to enter/hold).
- **kunlun Burst Chain** rewards never missing — pairs with precision items to run
  away with a fight. Keep the per-hit bonus small (`+2`) and streak-resettable.
- **Off-specialty penalty stacking.** −15% off-lane can compound with a physique
  off-lean (−15%) and low early mastery success rolls — an off-style, off-physique
  opener on run 3 could feel punishing. V1 keeps the penalty multiplicative and
  single-step (no per-family scaling); revisit if playtest shows hybrid openers
  are unviable rather than just weaker. Neutral/no-family content is never
  penalised, so a plain `improvised` chair or `basic_punch` is always safe.

## L. Deliberately locked for later (not V1)

- 4th technique stage (`master`) for slash's speed line beyond `lightning_slash`,
  and any 5-stage ladders.
- Off-specialty penalty in the headless `runGame` sim (V1 = client `CombatAdapter`
  only; the engine exports the map but registers no per-family `multiply` modifier).
- New armor / footwear combinable families (only `guard_bracers` /
  `dueling_dagger` were considered; deferred to V2 to keep the diff reviewable).
- `counter_punch` advanced/master line (reaction deepening lives under GUARD in V1).
- Master-rarity loot before run 8.
- Physique-specific *mechanics* (physique stays tradition-macro + reward-nudge;
  no per-physique modifiers on content yet).
- Enemy archetypes 9–12 (multi-hit fighter, precision fighter, etc.) and bosses
  4–5.

---

## M. Implementation phases (each = its own commit, tests + analyze green)

1. **This doc** (review checkpoint).
2. Engine — technique families: deepen punch/slash/guard to master, add
   palm/finger/kick, extend `TechniqueIds.bases`. Update `technique_content_test`,
   `technique_plugin_test`.
3. Engine — item families: `hand_wraps`, `polearm`/`rapier` combine chains.
   Update `item_content_test`, `item_combine_test`.
4. Engine — style affinity modifiers + **the 12 style specialties** (§E.1) +
   **off-specialty penalty** (§E.2): new stances (`sprawl`/`en_garde`/`swallow`),
   `spec:*` tags + modifier parts in `learnStyle`, exported `styleAlignedFamilies`
   + `multiply 0.85` off-lane modifiers, and the 9 style-gated martial techniques.
   Update `martial_*` tests.
5. Engine + client — enemies: expand `enemy_content.dart` with archetype fields;
   rebuild client `_enemyFor` into an archetype data table; wire `armour`/`dodge`/
   `missPunish`/`regen`/`hits` **and the `spec:*` combat hooks** (opening pre-empt,
   clinch dodge-ignore, riposte window, conditioning floor, redirect, swallow
   dodge, burst chain) through `CombatAdapter`. New/updated combat tests.
6. Client — reward contextual weighting + grown pools + `rarity`/`aff:` tag
   consumption. Update `reward_adapter` tests.
7. Engine + client — content validator test + `tool/validate_content.dart` +
   client reward-pool-id test.

Engine bump: after phases 2–5 land on engine `main`, bump the client `pubspec.yaml`
`ref:` and `flutter pub get` (per `build-engine-dependency` memory).
