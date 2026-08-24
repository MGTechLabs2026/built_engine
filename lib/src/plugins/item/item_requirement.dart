/// A generic mastery gate an `ItemDefinition` can require before it is
/// usable — reuses the existing `MasteryTracker`/`MasteryAtLeast`
/// machinery rather than inventing an item-specific mastery concept.
/// [masterySubject] is an arbitrary mastery subject string (typically,
/// but not necessarily, the item's own `item:<id>` subject — a future
/// item could just as well require mastery of an unrelated subject, e.g.
/// a martial style, purely by agreeing on the same subject string).
class ItemRequirement {
  const ItemRequirement({
    required this.masterySubject,
    required this.minimumLevel,
  });

  final String masterySubject;
  final int minimumLevel;
}
