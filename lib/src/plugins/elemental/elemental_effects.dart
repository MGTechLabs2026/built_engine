import 'package:build_engine/build_engine.dart';

import 'elemental_vocabulary.dart';

/// Applies the status tag associated with [element] — composes core's
/// existing `ApplyStatus` rather than reimplementing status mutation,
/// the same way MartialArts' rules compose `Heal`/`Damage`.
class ApplyElementalStatus implements Effect {
  const ApplyElementalStatus(this.element);

  final String element;

  @override
  void apply(RuleContext context) =>
      ApplyStatus(_statusFor(element)).apply(context);

  static String _statusFor(String element) => switch (element) {
        'fire' => ElementalStatuses.burning,
        'water' => ElementalStatuses.soaked,
        'lightning' => ElementalStatuses.shocked,
        _ => 'status:$element',
      };
}
