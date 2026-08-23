import '../components/health_component.dart';
import '../components/stat_component.dart';
import '../components/status_component.dart';
import '../components/tag_set.dart';
import 'effect_events.dart';
import 'rule_context.dart';

/// A Rule-scoped state mutation. Plugins implement this directly to add
/// their own effects — no registry required.
abstract class Effect {
  void apply(RuleContext context);
}

/// Reduces the subject's health by [amount], clamped to `[0, max]`.
/// Publishes [EntityDamaged], and additionally [EntityKilled] if health
/// reaches exactly 0. Does not destroy the entity — that stays a policy
/// decision for whoever reacts to [EntityKilled]. No-ops if the subject
/// has no [HealthComponent].
class Damage implements Effect {
  const Damage(this.amount);

  final num amount;

  @override
  void apply(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return;
    final health = context.components.get<HealthComponent>(subject);
    if (health == null) return;
    final wasAlreadyDead = health.current <= 0;
    final newCurrent = (health.current - amount).clamp(0, health.max);
    final applied = health.current - newCurrent;
    context.components.add(
      subject,
      HealthComponent(current: newCurrent, max: health.max),
    );
    context.events.publish(EntityDamaged(subject, applied));
    if (newCurrent == 0 && !wasAlreadyDead) {
      context.events.publish(EntityKilled(subject));
    }
  }
}

/// Increases the subject's health by [amount], clamped to `[0, max]`.
/// Publishes [EntityHealed]. No-ops if the subject has no
/// [HealthComponent].
class Heal implements Effect {
  const Heal(this.amount);

  final num amount;

  @override
  void apply(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return;
    final health = context.components.get<HealthComponent>(subject);
    if (health == null) return;
    final newCurrent = (health.current + amount).clamp(0, health.max);
    final applied = newCurrent - health.current;
    context.components.add(
      subject,
      HealthComponent(current: newCurrent, max: health.max),
    );
    context.events.publish(EntityHealed(subject, applied));
  }
}

/// Adds [delta] to the subject's named [stat], treating a missing
/// [StatComponent] or missing entry as `0`.
///
/// Stopgap: mutates the raw value directly. See `StatComponent`'s doc
/// comment — this will change once Modifier Engine lands.
class ModifyStat implements Effect {
  const ModifyStat(this.stat, this.delta);

  final String stat;
  final num delta;

  @override
  void apply(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return;
    final existing = context.components.get<StatComponent>(subject);
    final stats = Map<String, num>.of(existing?.stats ?? const <String, num>{});
    stats[stat] = (stats[stat] ?? 0) + delta;
    context.components.add(subject, StatComponent(stats));
  }
}

/// Adds [delta] to the subject's named [resource] via the shared
/// [RuleContext.resources] pool — floored at 0 (or the resource's
/// registered minimum) and capped at its registered maximum, if one has
/// been `define`d; unbounded above otherwise. Publishes [ResourceChanged]
/// through the same pool. No-ops if there is no subject.
class ModifyResource implements Effect {
  const ModifyResource(this.resource, this.delta);

  final String resource;
  final num delta;

  @override
  void apply(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return;
    context.resources.add(subject, resource, delta);
  }
}

/// Subtracts [amount] from the subject's named [resource] via
/// [RuleContext.resources] — silently no-ops (no mutation, no event) if
/// the subject cannot afford it, mirroring [Damage]/[Heal]'s existing
/// "no-op on an invalid precondition" convention rather than throwing.
/// Guard with a [ResourceAbove]/`canAfford` condition to detect the
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
/// [Damage]/[Heal]'s "no-op on an invalid precondition" convention,
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

/// Adds [status] to the subject's active statuses, creating the
/// [StatusComponent] if the subject doesn't have one yet.
class ApplyStatus implements Effect {
  const ApplyStatus(this.status);

  final String status;

  @override
  void apply(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return;
    final existing = context.components.get<StatusComponent>(subject);
    final statuses = Set<String>.of(existing?.activeStatuses ?? const <String>{});
    statuses.add(status);
    context.components.add(subject, StatusComponent(statuses));
  }
}

/// Removes [status] from the subject's active statuses. A no-op if the
/// subject has no [StatusComponent].
class RemoveStatus implements Effect {
  const RemoveStatus(this.status);

  final String status;

  @override
  void apply(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return;
    final existing = context.components.get<StatusComponent>(subject);
    if (existing == null) return;
    final statuses = Set<String>.of(existing.activeStatuses);
    statuses.remove(status);
    context.components.add(subject, StatusComponent(statuses));
  }
}

/// Adds [tag] to the subject's [TagSet], creating it if the subject
/// doesn't have one yet.
class AddTag implements Effect {
  const AddTag(this.tag);

  final String tag;

  @override
  void apply(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return;
    final existing = context.components.get<TagSet>(subject);
    final tags = Set<String>.of(existing?.tags ?? const <String>{});
    tags.add(tag);
    context.components.add(subject, TagSet(tags));
  }
}

/// Removes [tag] from the subject's [TagSet]. A no-op if the subject has
/// no [TagSet].
class RemoveTag implements Effect {
  const RemoveTag(this.tag);

  final String tag;

  @override
  void apply(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return;
    final existing = context.components.get<TagSet>(subject);
    if (existing == null) return;
    final tags = Set<String>.of(existing.tags);
    tags.remove(tag);
    context.components.add(subject, TagSet(tags));
  }
}

/// Creates a new entity (not the rule's subject) and, if [tags] is
/// non-empty, attaches a [TagSet]. Further initialization happens by
/// reacting to the `EntityCreated` event `EntityRegistry.create` already
/// publishes — no arbitrary component-initialization hook here.
class CreateEntity implements Effect {
  const CreateEntity({this.tags = const <String>{}});

  final Set<String> tags;

  @override
  void apply(RuleContext context) {
    final entity = context.entities.create();
    if (tags.isNotEmpty) {
      context.components.add(entity, TagSet(tags));
    }
  }
}

/// Destroys the rule's subject. Component cleanup stays the caller's job
/// via the `EntityDestroyed` subscription pattern documented in
/// `ARCHITECTURE.md` — this effect doesn't special-case it. A no-op if
/// the subject is already destroyed (rather than throwing), since two
/// rules reacting to different events could both target the same
/// subject for destruction.
class DestroyEntity implements Effect {
  const DestroyEntity();

  @override
  void apply(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return;
    if (!context.entities.isAlive(subject)) return;
    context.entities.destroy(subject);
  }
}

/// Replaces the subject's entire [TagSet] with [newTags] — a wholesale
/// identity swap, distinct from [AddTag]/[RemoveTag]'s single-tag
/// increments.
class TransformEntity implements Effect {
  const TransformEntity(this.newTags);

  final Set<String> newTags;

  @override
  void apply(RuleContext context) {
    final subject = context.subject;
    if (subject == null) return;
    context.components.add(subject, TagSet(newTags));
  }
}
