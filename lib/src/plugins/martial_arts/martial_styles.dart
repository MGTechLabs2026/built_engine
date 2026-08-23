import 'package:build_engine/build_engine.dart';

/// The three martial styles this plugin's vertical slice implements. Not
/// components — a style is a marker tag (`style:<id>`) granted by
/// [learnStyle]. `martial` is granted alongside it so any future content
/// plugin can query "is this a martial-arts practitioner" without knowing
/// which specific style.
abstract final class MartialStyles {
  static const boxing = 'boxing';
  static const shaolin = 'shaolin';
  static const taiChi = 'taiChi';
}

RuleContext _standaloneContext(EntityId subject, PluginContext context) =>
    RuleContext(
      subject: subject,
      triggerEvent: const Object(),
      entities: context.entities,
      components: context.components,
      events: context.events,
      rng: context.rng,
      eventCounts: context.rules.eventCounts,
    );

/// Grants [entity] the `martial` and `style:$styleId` tags. Learning
/// [MartialStyles.shaolin] additionally registers a permanent conditional
/// `Modifier` — `+4 add` to `palm`, active only while `stance:iron_body`
/// is present — implementing Shaolin's defensive-synergy-into-offense
/// mechanic entirely through the Modifier Engine. This content-specific
/// branch belongs here, in the content plugin, not in Core or Combat.
void learnStyle(EntityId entity, String styleId, PluginContext context) {
  final ctx = _standaloneContext(entity, context);
  const AddTag('martial').apply(ctx);
  AddTag('style:$styleId').apply(ctx);
  if (styleId == MartialStyles.shaolin) {
    context.modifiers.add(Modifier(
      source: ModifierSource('style:shaolin:synergy:${entity.value}'),
      target: entity,
      stat: 'palm',
      operation: ModifierOperation.add,
      value: 4,
      condition: HasTagQuery('stance:iron_body'),
    ));
  }
}
