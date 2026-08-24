/// The Item plugin's public surface — import this, never
/// `package:build_engine/src/plugins/item/...` directly.
library;

export 'src/plugins/item/item_content.dart'
    show itemContentDefinitions, itemDefinition, itemDefinitionFromContent;
export 'src/plugins/item/item_definition.dart';
export 'src/plugins/item/item_events.dart';
export 'src/plugins/item/item_instance.dart';
export 'src/plugins/item/item_lifecycle.dart';
export 'src/plugins/item/item_plugin.dart';
export 'src/plugins/item/item_requirement.dart';
export 'src/plugins/item/item_rules.dart';
export 'src/plugins/item/item_training_weights.dart';
export 'src/plugins/item/item_vocabulary.dart';
