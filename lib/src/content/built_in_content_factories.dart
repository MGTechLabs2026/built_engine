import '../entity/entity_registry.dart';
import '../rule/condition.dart';
import '../rule/effect.dart';
import '../rule/effect_events.dart';

import 'content_registry.dart';
import 'json_helpers.dart';

/// Registers factories for Core's own existing generic [Effect]/
/// [Condition]/event vocabulary against [registry] — called once, from
/// [ContentRegistry]'s constructor. Kept in its own file/function
/// (rather than inline in [ContentRegistry]) so the registry class
/// itself stays storage + lookup + orchestration only; this is Core's
/// own content vocabulary, not a plugin's, so it lives here rather than
/// being registered by some plugin instead (see `ARCHITECTURE_AUDIT.md`'s
/// finding #11).
void registerBuiltInContentFactories(ContentRegistry registry) {
  _registerBuiltInEffectFactories(registry);
  _registerBuiltInConditionFactories(registry);
  _registerBuiltInTriggers(registry);
}

void _registerBuiltInEffectFactories(ContentRegistry registry) {
  registry.registerEffectFactory(
      'damage', (p) => Damage(ContentField.requireNum(p, 'amount')));
  registry.registerEffectFactory(
      'heal', (p) => Heal(ContentField.requireNum(p, 'amount')));
  registry.registerEffectFactory(
      'modifyStat',
      (p) => ModifyStat(ContentField.requireString(p, 'stat'),
          ContentField.requireNum(p, 'delta')));
  registry.registerEffectFactory(
      'modifyResource',
      (p) => ModifyResource(ContentField.requireString(p, 'resource'),
          ContentField.requireNum(p, 'delta')));
  registry.registerEffectFactory('applyStatus',
      (p) => ApplyStatus(ContentField.requireString(p, 'status')));
  registry.registerEffectFactory('removeStatus',
      (p) => RemoveStatus(ContentField.requireString(p, 'status')));
  registry.registerEffectFactory(
      'addTag', (p) => AddTag(ContentField.requireString(p, 'tag')));
  registry.registerEffectFactory(
      'removeTag', (p) => RemoveTag(ContentField.requireString(p, 'tag')));
  registry.registerEffectFactory('createEntity',
      (p) => CreateEntity(tags: ContentField.optionalStringSet(p, 'tags')));
  registry.registerEffectFactory('destroyEntity', (p) => const DestroyEntity());
  registry.registerEffectFactory('transformEntity',
      (p) => TransformEntity(ContentField.optionalStringSet(p, 'tags')));
}

void _registerBuiltInConditionFactories(ContentRegistry registry) {
  registry.registerConditionFactory(
      'hasTag', (p) => HasTag(ContentField.requireString(p, 'tag')));
  registry.registerConditionFactory(
      'resourceAbove',
      (p) => ResourceAbove(ContentField.requireString(p, 'resource'),
          ContentField.requireNum(p, 'threshold')));
  registry.registerConditionFactory(
      'resourceBelow',
      (p) => ResourceBelow(ContentField.requireString(p, 'resource'),
          ContentField.requireNum(p, 'threshold')));
  registry.registerConditionFactory('healthBelow',
      (p) => HealthBelow(ContentField.requireNum(p, 'threshold')));
  registry.registerConditionFactory('statusActive',
      (p) => StatusActive(ContentField.requireString(p, 'status')));
  registry.registerConditionFactory(
      'randomChance',
      (p) =>
          RandomChance(ContentField.requireNum(p, 'probability').toDouble()));
}

void _registerBuiltInTriggers(ContentRegistry registry) {
  registry.registerTrigger(
      'EntityDamaged', EntityDamaged, (e) => (e as EntityDamaged).id);
  registry.registerTrigger(
      'EntityHealed', EntityHealed, (e) => (e as EntityHealed).id);
  registry.registerTrigger(
      'EntityKilled', EntityKilled, (e) => (e as EntityKilled).id);
  registry.registerTrigger(
      'EntityCreated', EntityCreated, (e) => (e as EntityCreated).id);
  registry.registerTrigger(
      'EntityDestroyed', EntityDestroyed, (e) => (e as EntityDestroyed).id);
}
