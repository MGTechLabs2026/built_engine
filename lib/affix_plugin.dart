/// The Affix plugin's public surface — import this, never
/// `package:build_engine/src/plugins/affix/...` directly.
library;

export 'src/plugins/affix/affix_mechanic.dart';
export 'src/plugins/affix/affix_types.dart';
export 'src/plugins/affix/affix_definition.dart'
    show AffixDefinition, affixDefinitionFromContent, affixDefinition;
export 'src/plugins/affix/affix_content.dart' show affixContentDefinitions;
export 'src/plugins/affix/affix_plugin.dart' show AffixPlugin;
export 'src/plugins/affix/affix_resolver.dart';
export 'src/plugins/affix/affix_application.dart'
    show applyAffixMechanic, AffixApplicationTarget, ItemInstanceTarget, CharacterTarget;
