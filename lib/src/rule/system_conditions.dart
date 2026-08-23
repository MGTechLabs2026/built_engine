import '../query/queries.dart';
import 'condition.dart';
import 'rule_context.dart';

/// The resource/progression/mastery/discovery verb family — split out of
/// `condition.dart` once that file grew to hold every generic check the
/// engine has ever added (see `ARCHITECTURE_AUDIT.md`'s god-class
/// finding). `Condition`'s original core checks (`HasTag`/`HasComponent`/
/// `ResourceAbove`/`ResourceBelow`/`HealthBelow`/`StatusActive`/
/// `EventCount`/`RandomChance`) stay in `condition.dart`; everything added
/// across the Progression, Mastery, and Discovery passes lives here
/// instead. No behavior changed by this split — every class below is
/// unchanged from its prior home, just relocated.

/// Matches when the rule's subject's tier for the named progression
/// [subject] is strictly greater than [tier], via the shared
/// `RuleContext.progression` engine. Delegates to `ProgressionEngine`
/// directly rather than a `Query` — like `EventCount`/`RandomChance`, it
/// needs a service (`RuleContext.progression`'s registered thresholds)
/// that `QueryScope` doesn't carry, so duplicating those thresholds into a
/// second, Query-level constructor parameter would risk drifting from
/// whatever was actually `define`d.
class ProgressionTierAbove implements Condition {
  const ProgressionTierAbove(this.subject, this.tier);

  final String subject;
  final int tier;

  @override
  bool evaluate(RuleContext context) {
    final entity = context.subject;
    if (entity == null) return false;
    return context.progression.tierOf(entity, subject) > tier;
  }
}

/// Matches when the rule's subject's tier for the named progression
/// [subject] is strictly less than [tier]. See [ProgressionTierAbove] for
/// why this delegates to `RuleContext.progression` rather than a `Query`.
class ProgressionTierBelow implements Condition {
  const ProgressionTierBelow(this.subject, this.tier);

  final String subject;
  final int tier;

  @override
  bool evaluate(RuleContext context) {
    final entity = context.subject;
    if (entity == null) return false;
    return context.progression.tierOf(entity, subject) < tier;
  }
}

/// Matches when the rule's subject's mastery level for the named [subject]
/// is at least [level], via the shared `RuleContext.mastery` tracker.
/// Usable by any plugin for any mastery subject — no `SwordMastery`/
/// `TechniqueMastery` special-casing. Delegates directly to
/// `MasteryTracker.levelOf` rather than a `Query`, for the same reason
/// [ProgressionTierAbove] does: the registered thresholds live in the
/// tracker, not in anything `QueryScope` carries.
class MasteryAtLeast implements Condition {
  const MasteryAtLeast(this.subject, this.level);

  final String subject;
  final int level;

  @override
  bool evaluate(RuleContext context) {
    final owner = context.subject;
    if (owner == null) return false;
    return context.mastery.levelOf(owner, subject) >= level;
  }
}

/// Matches when the rule's subject has at least discovered the named
/// content [subject] (discovered or unlocked). See `DiscoveredQuery`.
class IsDiscovered implements Condition {
  const IsDiscovered(this.subject);

  final String subject;

  @override
  bool evaluate(RuleContext context) {
    final entity = context.subject;
    if (entity == null) return false;
    return DiscoveredQuery(subject).matches(entity, scopeOf(context));
  }
}

/// Matches when the rule's subject has unlocked the named content
/// [subject] specifically. See `UnlockedQuery`.
class IsUnlocked implements Condition {
  const IsUnlocked(this.subject);

  final String subject;

  @override
  bool evaluate(RuleContext context) {
    final entity = context.subject;
    if (entity == null) return false;
    return UnlockedQuery(subject).matches(entity, scopeOf(context));
  }
}
