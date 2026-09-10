import 'dart:math' as math;

import 'package:build_engine/build_engine.dart';
import 'package:build_engine/item_plugin.dart';

import 'affix_definition.dart';
import 'affix_mechanic.dart';

/// Where a resolved affix's mechanics land. Item-domain rewards pass an
/// [ItemInstanceTarget] (the freshly-owned copy); technique-domain
/// rewards pass a [CharacterTarget].
sealed class AffixApplicationTarget {
  const AffixApplicationTarget();
}

class ItemInstanceTarget extends AffixApplicationTarget {
  const ItemInstanceTarget({required this.instance, required this.itemId});
  final EntityId instance;
  final String itemId;
}

class CharacterTarget extends AffixApplicationTarget {
  const CharacterTarget({required this.character});
  final EntityId character;
}

/// Applies [def]'s single [AffixMechanic] to [target] and returns the
/// canonical `stat` string for the Almanac snapshot — always non-null
/// and target-independent: the mechanic *kind* string
/// (`'weapon_stat_bonus'` for [WeaponStatBonus], `'heal'` for
/// [ImmediateHeal], `'bank_progression'` for [BankProgression]).
/// [WeaponStatBonus] still binds the *resolved* [WeaponStatTags] stat to
/// [ItemInstance.statBonuses] via `addItemStatBonuses` — only the
/// returned `stat` is the target-independent kind, because
/// `AffixSnapshot` holds exactly one canonical snapshot per `affixId`
/// and a per-target value would break cross-run / hydrated recording.
///
/// A mechanic / target mismatch throws [ArgumentError] — unreachable
/// from validated content (the `affix_pool:*` tag fixes the domain), a
/// belt-and-braces guard against a composition bug.
({String stat}) applyAffixMechanic(
  AffixDefinition def,
  AffixApplicationTarget target,
  PluginContext context,
) {
  final mechanic = def.mechanic;
  switch (mechanic) {
    case WeaponStatBonus(:final amount):
      if (target is! ItemInstanceTarget) {
        throw ArgumentError('WeaponStatBonus (${def.id}) needs an ItemInstanceTarget');
      }
      final resolvedStat = WeaponStatTags.matchOrFallback(
        itemDefinition(target.itemId, context).tags,
        'item:${target.itemId}',
      );
      addItemStatBonuses(target.instance, {resolvedStat: amount}, context);
      return (stat: 'weapon_stat_bonus');

    case ImmediateHeal(:final amount):
      if (target is! CharacterTarget) {
        throw ArgumentError('ImmediateHeal (${def.id}) needs a CharacterTarget');
      }
      final health = context.components.get<HealthComponent>(target.character);
      if (health != null) {
        context.components.add(
          target.character,
          HealthComponent(
            current: math.min(health.current + amount, health.max),
            max: health.max,
          ),
        );
      }
      return (stat: 'heal');

    case BankProgression(:final amount):
      if (target is! CharacterTarget) {
        throw ArgumentError('BankProgression (${def.id}) needs a CharacterTarget');
      }
      context.resources.add(target.character, ItemResources.upgradePoints, amount);
      return (stat: 'bank_progression');
  }
}
