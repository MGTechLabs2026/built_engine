/// The Consumable plugin's public surface — import this, never
/// `package:build_engine/src/plugins/consumable/...` directly.
library;

export 'src/plugins/consumable/consumable_content.dart'
    show
        consumableContentDefinitions,
        consumableDefinition,
        consumableDefinitionFromContent;
export 'src/plugins/consumable/consumable_definition.dart';
export 'src/plugins/consumable/consumable_plugin.dart';
export 'src/plugins/consumable/consumable_vocabulary.dart';
