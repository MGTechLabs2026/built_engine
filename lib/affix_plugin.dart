/// The Affix plugin's public surface — import this, never
/// `package:build_engine/src/plugins/affix/...` directly.
library;

export 'src/plugins/affix/affix_mechanic.dart';
export 'src/plugins/affix/affix_types.dart';
export 'src/plugins/affix/affix_definition.dart'
    show AffixDefinition, affixDefinitionFromContent, affixDefinition;
