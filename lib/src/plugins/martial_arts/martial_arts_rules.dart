import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';

import 'martial_conditions.dart';
import 'martial_vocabulary.dart';

/// The 4 rules that give MartialArts its cross-entity behavior — all
/// reacting to Combat's existing public events, never intercepting
/// `AttackAction`/`Damage` directly (which would require modifying
/// Combat). Registered by `MartialArtsPlugin.initialize`.
///
/// The two `_passiveResourceRegenRule` calls read
/// `MartialItemIds.momentumTrinket`/`MartialItemIds.qiPendant` rather
/// than a second, independently-typed `'momentum_trinket'`/`'qi_pendant'`
/// literal — a renamed trinket id would otherwise silently break the
/// rule that's supposed to react to it (`ARCHITECTURE_AUDIT.md`'s
/// observation B).
List<Rule> buildMartialArtsRules() => [
      _shaolinDefensiveSynergyRule(),
      _taiChiCounterRule(),
      _passiveResourceRegenRule(
        requiresTag: 'equipped:${MartialItemIds.momentumTrinket}',
        resource: MartialResources.momentum,
        amount: 3,
      ),
      _passiveResourceRegenRule(
        requiresTag: 'equipped:${MartialItemIds.qiPendant}',
        resource: MartialResources.qi,
        amount: 2,
      ),
    ];

/// WHEN a Shaolin entity in `stance:iron_body` takes damage, heal back a
/// portion of it. A reactive mitigation, not a block — `Damage`/
/// `AttackAction` are never touched.
Rule _shaolinDefensiveSynergyRule() => Rule(
      trigger: EntityDamaged,
      subjectOf: (event) => (event as EntityDamaged).id,
      conditions: const [HasTag(MartialStances.ironBody)],
      effects: const [Heal(2)],
    );

/// WHEN any action completes against a target with `stance:tai_chi`,
/// redirect some damage back onto the attacker — regardless of what kind
/// of action or attacker it was.
Rule _taiChiCounterRule() => Rule(
      trigger: ActionCompleted,
      subjectOf: (event) => (event as ActionCompleted).actor,
      conditions: const [TaiChiCounterCondition()],
      effects: const [Damage(3)],
    );

/// One data-driven factory, called once per passive-regen trinket, rather
/// than two near-duplicate rules.
Rule _passiveResourceRegenRule({
  required String requiresTag,
  required String resource,
  required num amount,
}) =>
    Rule(
      trigger: TurnStarted,
      subjectOf: (event) => (event as TurnStarted).actor,
      conditions: [HasTag(requiresTag)],
      effects: [ModifyResource(resource, amount)],
    );
