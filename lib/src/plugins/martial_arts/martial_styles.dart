import 'package:build_engine/build_engine.dart';

import 'martial_vocabulary.dart';

/// The six martial styles this plugin implements — three western, three
/// eastern (`martialTraditionOf`), one archetype apiece (offense/defense/
/// speed) purely as a naming rationale, not a mechanical tag system:
/// polearming=reach, wrestling=defense, fencing=speed (western); shaolin=
/// offense, taiChi=defense, kunlun=speed (eastern). Not components — a
/// style is a marker tag (`style:<id>`) granted by [learnStyle]. `martial`
/// is granted alongside it so any future content plugin can query "is
/// this a martial-arts practitioner" without knowing which specific
/// style.
abstract final class MartialStyles {
  static const polearming = 'polearming';
  static const wrestling = 'wrestling';
  static const fencing = 'fencing';
  static const shaolin = 'shaolin';
  static const taiChi = 'taiChi';
  static const kunlun = 'kunlun';
}

/// Grants [entity] the `martial`, `style:$styleId`, and broad-tradition
/// (`'western'`/`'eastern'`) tags. The tradition tag is the one generic
/// interoperability hook another plugin (e.g. Physique) needs to react
/// to "which martial tradition is this character trained in" without
/// either plugin importing the other. It reuses vocabulary MartialArts
/// already owns: individual technique content
/// (`martial_technique_content.dart`) is already tagged
/// `'western'`/`'eastern'` per technique; this just makes the same fact
/// available on the entity itself. A style id outside this plugin's
/// three known styles is still accepted (this plugin doesn't validate
/// style ids) — it simply receives no tradition tag.
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
  final traditionTag = martialTraditionOf(styleId);
  if (traditionTag != null) {
    AddTag(traditionTag).apply(ctx);
  }
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

/// The broad martial tradition [styleId] belongs to, or `null` for a
/// style id outside this plugin's six known styles — an entity may
/// still learn an unrecognized style (this plugin's vertical slice
/// doesn't gate that), it simply gets no tradition tag, so nothing
/// downstream (e.g. Physique's synergy modifiers) reacts to it. Public
/// so a game composition layer (e.g. a client's character-creation
/// screen) can determine a style's tradition before the player commits
/// to it, not only after [learnStyle] has already applied the tag.
String? martialTraditionOf(String styleId) => switch (styleId) {
      MartialStyles.polearming ||
      MartialStyles.wrestling ||
      MartialStyles.fencing =>
        MartialTraditions.western,
      MartialStyles.shaolin || MartialStyles.taiChi || MartialStyles.kunlun =>
        MartialTraditions.eastern,
      _ => null,
    };

/// The style ids belonging to [tradition] (`MartialTraditions.western`/
/// `.eastern`) — the public inverse of [martialTraditionOf], for callers
/// outside this plugin (e.g. a game composition layer offering "pick
/// your starting style" once a tradition is chosen) that need to go
/// from tradition to its styles rather than the other way around, so
/// they never have to re-derive this plugin's own style/tradition
/// mapping independently. An unrecognized [tradition] returns an empty
/// list, matching [martialTraditionOf]'s own "no assumption" behavior for
/// an unrecognized style.
List<String> stylesForTradition(String tradition) => switch (tradition) {
      MartialTraditions.western => const [MartialStyles.polearming, MartialStyles.wrestling, MartialStyles.fencing],
      MartialTraditions.eastern => const [MartialStyles.shaolin, MartialStyles.taiChi, MartialStyles.kunlun],
      _ => const [],
    };
