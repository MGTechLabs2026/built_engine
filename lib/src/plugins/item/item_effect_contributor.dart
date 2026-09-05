import 'package:build_engine/build_engine.dart';

import 'item_definition.dart';
import 'item_instance.dart';
import 'weapon_stat_tags.dart';

/// [ItemDefinition] + optional [ItemInstance] as one `EffectContributor`
/// — an item needs both content-level state (scaled `attack`, its combat
/// stat tag) and per-copy state (`itemClass`, `statBonuses`) to compose
/// its profile, and neither type alone can see both, so this is a thin
/// composing wrapper rather than either type implementing the interface
/// directly. [instance] is `null` for a legacy null-`instanceEntityId`
/// placement — scaling then falls back to class 1 (today's own fallback,
/// `itemClass ?? 1`), and `statBonuses` contributes nothing (there is no
/// copy to read them from).
///
/// Everything an item currently contributes is `supporting` — counted
/// while hung, nothing yet while merely owned or specifically "used"
/// (this migration is representation-only; see spec §5).
class ItemEffectContributor implements EffectContributor {
  const ItemEffectContributor(this.definition, this.instance);

  final ItemDefinition definition;
  final ItemInstance? instance;

  @override
  EffectProfile effectProfile() {
    final itemClass = instance?.itemClass ?? 1;
    final supporting = <String, num>{};

    final attack = definition.scaledProperties(itemClass)['attack'];
    if (attack != null) {
      final stat = _statFor(definition);
      supporting[stat] = (supporting[stat] ?? 0) + attack;
    }

    instance?.statBonuses.forEach((stat, value) {
      supporting[stat] = (supporting[stat] ?? 0) + value;
    });

    if (supporting.isEmpty) return EffectProfile.empty;
    return EffectProfile.of({EffectTier.supporting: supporting});
  }

  String _statFor(ItemDefinition item) =>
      WeaponStatTags.matchOrFallback(item.tags, 'item:${item.id}');
}
