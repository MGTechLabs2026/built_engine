import 'effect.dart';
import 'rule_context.dart';

/// The resource/progression/mastery/discovery verb family — split out of
/// `effect.dart` once that file grew to hold every generic verb the
/// engine has ever added (see `ARCHITECTURE_AUDIT.md`'s god-class
/// finding). `Effect`'s original core verbs (`Damage`/`Heal`/
/// `ModifyStat`/`ModifyResource`/`ApplyStatus`/`RemoveStatus`/tag/entity
/// effects) stay in `effect.dart`; everything added across the Resource
/// Engine, Progression, Mastery, and Discovery passes lives here instead.
/// No behavior changed by this split — every class below is unchanged
/// from its prior home, just relocated.

/// Subtracts [amount] from the subject's named [resource] via
/// [RuleContext.resources] — silently no-ops (no mutation, no event) if
/// the subject cannot afford it, mirroring `Damage`/`Heal`'s existing
/// "no-op on an invalid precondition" convention rather than throwing.
/// Guard with a `ResourceAbove`/`canAfford` condition to detect the
/// insufficient case instead of relying on this effect's silence.
class ConsumeResource implements Effect {
  const ConsumeResource(this.resource, this.amount);

  final String resource;
  final num amount;

  @override
  void apply(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return;
    if (!context.resources.canAfford(subject, resource, amount)) return;
    context.resources.consume(subject, resource, amount);
  }
}

/// Adds [amount] to the subject's named [resource] via
/// [RuleContext.resources], clamped to its registered maximum. Always
/// succeeds. No-ops only if there is no subject.
class RestoreResource implements Effect {
  const RestoreResource(this.resource, this.amount);

  final String resource;
  final num amount;

  @override
  void apply(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return;
    context.resources.restore(subject, resource, amount);
  }
}

/// Adds [amount] (may be negative) to the subject's experience for the
/// named progression [subject], via the shared
/// `RuleContext.progression` engine — floored at 0, tier-crossing events
/// published automatically. No-ops if there is no subject.
class GrantProgressionExperience implements Effect {
  const GrantProgressionExperience(this.subject, this.amount);

  final String subject;
  final num amount;

  @override
  void apply(RuleContext context) {
    final entity = context.subject;
    if (entity == null) return;
    context.progression.addExperience(entity, subject, amount);
  }
}

/// Sets the subject's experience for the named progression [subject] to
/// at least [tier]'s registered threshold, via
/// `RuleContext.progression.unlock`. Silently no-ops — matching
/// `Damage`/`Heal`'s "no-op on an invalid precondition" convention,
/// Effects never throw in this engine — if [tier] is below 1 or beyond
/// [subject]'s registered thresholds, rather than throwing the way
/// `ProgressionEngine.unlock` does for a direct imperative caller.
class UnlockProgressionTier implements Effect {
  const UnlockProgressionTier(this.subject, this.tier);

  final String subject;
  final int tier;

  @override
  void apply(RuleContext context) {
    final entity = context.subject;
    if (entity == null) return;
    final definition = context.progression.definitionOf(subject);
    if (tier < 1 || definition == null || tier > definition.thresholds.length) {
      return;
    }
    context.progression.unlock(entity, subject, tier);
  }
}

/// Adds [amount] (may be negative) to the subject's mastery progress for
/// the named [subject], via the shared `RuleContext.mastery` tracker —
/// floored at 0, level-crossing events published automatically. Usable by
/// any plugin for any mastery subject. No-ops if there is no subject.
class IncreaseMastery implements Effect {
  const IncreaseMastery(this.subject, this.amount);

  final String subject;
  final num amount;

  @override
  void apply(RuleContext context) {
    final owner = context.subject;
    if (owner == null) return;
    context.mastery.increase(owner, subject, amount);
  }
}

/// Moves the subject's discovery state for the named content [subject]
/// from `unknown` to `discovered`, via the shared `RuleContext.discovery`
/// tracker. No-ops (including no event) if already discovered/unlocked.
class DiscoverSubject implements Effect {
  const DiscoverSubject(this.subject);

  final String subject;

  @override
  void apply(RuleContext context) {
    final entity = context.subject;
    if (entity == null) return;
    context.discovery.discover(entity, subject);
  }
}

/// Moves the subject's discovery state for the named content [subject] to
/// `unlocked`, via the shared `RuleContext.discovery` tracker —
/// auto-promoting through `discovered` first if still `unknown`. No-ops if
/// already unlocked.
class UnlockSubject implements Effect {
  const UnlockSubject(this.subject);

  final String subject;

  @override
  void apply(RuleContext context) {
    final entity = context.subject;
    if (entity == null) return;
    context.discovery.unlock(entity, subject);
  }
}
