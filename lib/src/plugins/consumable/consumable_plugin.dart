import 'package:build_engine/build_engine.dart';

import 'consumable_content.dart';
import 'consumable_definition.dart';
import 'consumable_vocabulary.dart';

/// The Consumable plugin: per-fight limited-use items (heal potion,
/// firebomb, tonics), built with `PluginSdk`, depending on nothing but
/// Core — a fourth proof after Elemental / Item / Technique. Owns
/// `referenceType: 'consumable'`. No Combat dependency, no trigger
/// registration, no plugin-order constraint.
///
/// Charge pools (`consumable:<id>`) are defined `max: double.infinity`
/// (SP3 §5.1.1): the stored value is the aggregate over every hung copy,
/// written authoritatively by `ConsumableBinder.grant` each fight, not a
/// single copy's `charges`.
class ConsumablePlugin extends GamePlugin {
  @override
  String get id => 'consumable';

  @override
  String get version => '0.1.0';

  late PluginSdk sdk;

  @override
  void initialize(PluginContext context) {
    sdk = PluginSdk(context);
    sdk.registerTag('consumable', description: 'A per-fight limited-use item.');

    // ContentRegistry has no unload — guard against a second load.
    if (context.content.find(ConsumableIds.healPotion) == null) {
      sdk.registerContentBatch(consumableContentDefinitions);
    }

    for (final json in consumableContentDefinitions) {
      final id = json['id'] as String;
      final ConsumableDefinition def;
      try {
        def = consumableDefinitionFromContent(context.content.get(id));
      } on ContentFieldException catch (e) {
        throw ContentValidationException(id, e); // same as ContentRegistry._parse
      }
      context.resources.define(ResourceDefinition(
        id: consumableChargeResource(def.id),
        min: 0,
        max: double.infinity,
      ));
    }
  }

  @override
  void unregister(PluginContext context) {
    sdk.disposeAll();
  }
}
