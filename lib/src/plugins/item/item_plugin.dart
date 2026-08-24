import 'package:build_engine/build_engine.dart';

import 'item_content.dart';
import 'item_instance.dart';
import 'item_rules.dart';
import 'item_vocabulary.dart';

/// The Item plugin: generic physical equipment (Knife, Iron Sword,
/// Gloves, Training Staff, Cloth Armor, Training Shoes), built entirely
/// with `PluginSdk`, depending on nothing but Core — not Combat, not
/// MartialArts, not Elemental. A second proof (after `ElementalPlugin`)
/// that "copy Elemental, not MartialArts" produces a fully decoupled
/// content plugin.
///
/// Tome rejection of an unusable item is enforced at `addItemToTome`
/// (`item_lifecycle.dart`), not inside `TomeService`/`Container`:
/// `PlacementRule.isSatisfied(ContainerView, EntityId item, Set<SlotId>)`
/// has no owner parameter, so a placement rule has no way to look up
/// *whose* Discovery/Mastery state to check — `Container` is deliberately
/// content-agnostic and shared by any future container shape (backpack,
/// weapon rack, skill board), not just the Tome. Gating at the plugin's
/// own call boundary into `TomeService.insert` needs no Core/Tome change
/// at all, per the milestone's "do not modify Tome internals
/// unnecessarily."
class ItemPlugin extends GamePlugin {
  @override
  String get id => 'item';

  @override
  String get version => '0.1.0';

  /// Constructed in [initialize]; not `late final` since a plugin can be
  /// `initialize`d again after `unregister`.
  late PluginSdk sdk;

  @override
  void initialize(PluginContext context) {
    sdk = PluginSdk(context);
    sdk.registerComponentCleanup<ItemInstance>();

    sdk.registerTag('item', description: 'Generic physical equipment.');
    sdk.registerTag(ItemCategories.weapon, description: 'A wielded weapon item.');
    sdk.registerTag(ItemCategories.armor, description: 'A worn armor item.');
    sdk.registerTag(ItemCategories.footwear, description: 'A worn footwear item.');

    // ContentRegistry has no unload operation, so content loaded here
    // outlives unregister — guard against loading it twice if this
    // plugin is initialize()d again on the same context afterward.
    if (context.content.find(ItemIds.knife) == null) {
      sdk.registerContentBatch(itemContentDefinitions);
    }

    for (final json in itemContentDefinitions) {
      final masteryRaw = (json['requirements'] as Map?)?['mastery'] as Map?;
      final thresholds = masteryRaw?['thresholds'] as List?;
      if (masteryRaw != null && thresholds != null) {
        context.mastery.define(MasteryDefinition(
          subject: masteryRaw['subject'] as String,
          thresholds: thresholds.cast<num>(),
        ));
      }
    }

    final definitions = [
      for (final json in itemContentDefinitions)
        itemDefinition(json['id'] as String, context),
    ];
    for (final rule in buildItemUsabilityRules(definitions)) {
      sdk.registerRule(rule);
    }
  }

  /// Mirrors [initialize]: cancels every subscription taken out there —
  /// component cleanup and every item's usability rule — so an
  /// unregistered `ItemPlugin` stops reacting to events entirely, the
  /// same teardown discipline every other plugin in this engine follows.
  @override
  void unregister(PluginContext context) {
    sdk.disposeAll();
  }
}
