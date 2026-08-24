import 'package:build_engine/build_engine.dart';

import 'item_definition.dart';
import 'item_vocabulary.dart';

/// One `Rule` per item with a real mastery requirement
/// (`minimumLevel > 0`): `WHEN MasteryLevelReached IF mastery(item) >=
/// minimum THEN unlock the item's discovery subject` — the generic
/// mirror of the milestone brief's `ItemBecameUsable` event, reusing
/// `SubjectUnlocked` (fired by `UnlockSubject`) rather than adding a new
/// event type. Items with no requirement (or `minimumLevel <= 0`) need
/// no rule — `discoverItem` already unlocks them immediately, since
/// there's no threshold left to cross.
List<Rule> buildItemUsabilityRules(List<ItemDefinition> definitions) => [
      for (final item in definitions)
        if (item.requirement != null && item.requirement!.minimumLevel > 0)
          Rule(
            trigger: MasteryLevelReached,
            subjectOf: (event) => (event as MasteryLevelReached).owner,
            conditions: [
              MasteryAtLeast(
                item.requirement!.masterySubject,
                item.requirement!.minimumLevel,
              ),
            ],
            effects: [UnlockSubject(itemSubject(item.id))],
          ),
    ];
