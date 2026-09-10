import 'package:build_engine/build_engine.dart' show ContentFieldException;

/// The single mechanical effect an affix carries. Closed union: exactly
/// three variants in v1. `amount` is the canonical magnitude the engine
/// owns; nothing infers it from a label.
sealed class AffixMechanic {
  const AffixMechanic();

  num get amount;

  /// Parses a `{"kind": ..., "amount": ...}` object. Throws
  /// [ContentFieldException] (path `mechanic.kind` / `mechanic.amount`)
  /// on an unknown kind or a missing / non-numeric amount — the same
  /// exception `ContentRegistry` wraps as `ContentValidationException`.
  factory AffixMechanic.fromJson(Map<String, dynamic> json) {
    final amount = json['amount'];
    if (amount is! num) {
      throw ContentFieldException('mechanic.amount', 'required num field missing or not a number');
    }
    switch (json['kind']) {
      case 'weapon_stat_bonus':
        return WeaponStatBonus(amount);
      case 'heal':
        return ImmediateHeal(amount);
      case 'bank_progression':
        return BankProgression(amount);
      default:
        throw ContentFieldException('mechanic.kind', 'unknown affix mechanic kind: ${json['kind']}');
    }
  }
}

/// A flat bonus to an item copy's resolved weapon stat (bound via
/// `addItemStatBonuses`). Item-domain affixes only.
class WeaponStatBonus extends AffixMechanic {
  const WeaponStatBonus(this.amount);
  @override
  final num amount;
}

/// Restore `amount` vitality immediately. Technique-domain affixes only.
class ImmediateHeal extends AffixMechanic {
  const ImmediateHeal(this.amount);
  @override
  final num amount;
}

/// Bank `amount` extra upgrade points. Technique-domain affixes only.
class BankProgression extends AffixMechanic {
  const BankProgression(this.amount);
  @override
  final num amount;
}
