import 'package:build_engine/build_engine.dart';

import 'martial_vocabulary.dart';

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

/// Grants [entity] the `martial`, `style:$styleId`, and broad-tradition
/// (`'western'`/`'eastern'`) tags. The tradition tag is the one generic
/// interoperability hook another plugin (e.g. Physique) needs to react
/// to "which martial tradition is this character trained in" without
/// either plugin importing the other. It reuses vocabulary MartialArts
/// already owns: individual technique content
/// (`martial_technique_content.dart`) is already tagged
/// `'western'`/`'eastern'` per technique; this just makes the same fact
/// available on the entity itself.
///
/// Learning [MartialStyles.shaolin] additionally registers a permanent
/// conditional `Modifier` — `+4 add` to `palm`, active only while
/// `stance:iron_body` is present — implementing Shaolin's
/// defensive-synergy-into-offense mechanic entirely through the Modifier
/// Engine. This content-specific branch belongs here, in the content
/// plugin, not in Core or Combat.
void learnStyle(EntityId entity, String styleId, PluginContext context) {
  final ctx = context.ruleContextFor(entity);
  const AddTag('martial').apply(ctx);
  AddTag('style:$styleId').apply(ctx);
  AddTag(_traditionTagFor(styleId)).apply(ctx);
  if (styleId == MartialStyles.shaolin) {
    context.modifiers.add(Modifier(
      source: ModifierSource('style:shaolin:synergy:${entity.value}'),
      target: entity,
      stat: 'palm',
      operation: ModifierOperation.add,
      value: 4,
      condition: HasTagQuery(MartialStances.ironBody),
    ));
  }
}

/// The broad martial tradition [styleId] belongs to.
String _traditionTagFor(String styleId) => switch (styleId) {
      MartialStyles.boxing => 'western',
      MartialStyles.shaolin || MartialStyles.taiChi => 'eastern',
      _ => throw ArgumentError('unknown style id: $styleId'),
    };
