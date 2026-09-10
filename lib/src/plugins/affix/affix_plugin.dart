import 'package:build_engine/build_engine.dart';

import 'affix_content.dart';
import 'affix_definition.dart';
import 'affix_mechanic.dart';
import 'affix_types.dart';

/// The Affix plugin: canonical reward-affix content (`type: 'affix'`),
/// enumerated by `affix_pool:*` tags. Pure content — no components, no
/// rules, no resources, no plugin-order constraint beyond needing the
/// Item / Technique content domains present when the resolver runs (the
/// harness initializes it after both). Modelled on `ConsumablePlugin`.
class AffixPlugin extends GamePlugin {
  @override
  String get id => 'affix';

  @override
  String get version => '0.1.0';

  late PluginSdk sdk;

  @override
  void initialize(PluginContext context) {
    sdk = PluginSdk(context);
    sdk.registerTag('affix', description: 'A reward affix (prefix / suffix).');
    for (final lean in const ['neutral', 'force', 'flow']) {
      sdk.registerTag('lean:$lean', description: 'Affix affinity lean.');
    }
    for (final cat in AffixCategories.all) {
      sdk.registerTag('affix_pool:$cat', description: 'Affix reward pool: $cat.');
    }

    // ContentRegistry has no unload — guard against loading twice.
    // Check if any affix is already loaded; if so, skip batch registration.
    if (context.content.withTag('affix').isEmpty) {
      sdk.registerContentBatch(affixContentDefinitions);
    }

    // Validate every loaded affix through the production parse path, then check
    // the pool ⇔ mechanic-family correspondence.
    final loadedAffixes = context.content.withTag('affix');
    for (final contentDef in loadedAffixes) {
      final defId = contentDef.id;
      try {
        final def = affixDefinitionFromContent(contentDef);
        final isItemPool = def.category == AffixCategories.itemPrefix ||
            def.category == AffixCategories.itemSuffix;
        final isStatMechanic = def.mechanic is WeaponStatBonus;
        if (isItemPool != isStatMechanic) {
          throw ContentFieldException(
            'mechanic.kind',
            'item pools require weapon_stat_bonus; technique pools require heal / bank_progression',
          );
        }
      } on ContentFieldException catch (e) {
        throw ContentValidationException(defId, e);
      }
    }
  }

  @override
  void unregister(PluginContext context) => sdk.disposeAll();
}
