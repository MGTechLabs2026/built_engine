/// The Technique plugin's public surface — import this, never
/// `package:build_engine/src/plugins/technique/...` directly.
library;

export 'src/plugins/technique/technique_content.dart'
    show techniqueContentDefinitions, techniqueDefinition, techniqueDefinitionFromContent;
export 'src/plugins/technique/technique_definition.dart';
export 'src/plugins/technique/technique_descriptor.dart';
export 'src/plugins/technique/technique_descriptor_content.dart';
export 'src/plugins/technique/technique_evolution.dart';
export 'src/plugins/technique/technique_events.dart';
export 'src/plugins/technique/technique_lifecycle.dart';
export 'src/plugins/technique/technique_plugin.dart';
export 'src/plugins/technique/technique_training_weights.dart';
export 'src/plugins/technique/technique_variant.dart';
export 'src/plugins/technique/technique_variant_lifecycle.dart';
export 'src/plugins/technique/technique_variant_resolver.dart';
export 'src/plugins/technique/technique_vocabulary.dart';
