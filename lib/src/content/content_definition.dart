import '../rule/condition.dart';
import '../rule/effect.dart';
import '../rule/rule.dart';

/// A single piece of data-defined content — an item, skill, style,
/// spell, trinket, or status. [type] is an opaque label the registry
/// stores and indexes but never interprets. See the Content Registry
/// design spec (`docs/superpowers/specs/2026-08-23-content-registry-design.md`)
/// for the full field-by-field JSON shape this is parsed from.
class ContentDefinition {
  const ContentDefinition({
    required this.id,
    required this.type,
    required this.tags,
    required this.costEffects,
    required this.conditions,
    required this.effects,
    required this.requires,
    required this.extra,
    required this.raw,
  });

  final String id;
  final String type;
  final Set<String> tags;

  /// Zero or one entries, parsed from the JSON `components.cost` object
  /// (`{"resource": ..., "amount": ...}`) into a single
  /// `ModifyResource(resource, -amount)`. No content in this engine has
  /// ever needed more than one resource cost.
  final List<Effect> costEffects;

  final List<Condition> conditions;
  final List<Effect> effects;

  /// Other content/rule ids that must be registered for this definition
  /// to be valid. Checked by `ContentRegistry` at load time, not stored
  /// as a live reference.
  final Set<String> requires;

  /// Every top-level JSON field this class didn't otherwise interpret,
  /// verbatim — including any `components` entry besides `cost` (e.g.
  /// `claude.md`'s own `iron_sword` example's `components.attack`).
  final Map<String, dynamic> extra;

  /// The exact input map this definition was parsed from, for lossless
  /// re-export via `ContentRegistry.toJson()`.
  final Map<String, dynamic> raw;
}

/// A data-defined [Rule] — `trigger`/`subjectOf` resolved via a
/// registered trigger descriptor (see `ContentRegistry.registerTrigger`).
/// Shares its id space with [ContentDefinition] inside `ContentRegistry`.
class RuleDefinition {
  const RuleDefinition({
    required this.id,
    required this.rule,
    required this.raw,
  });

  final String id;
  final Rule rule;
  final Map<String, dynamic> raw;
}
