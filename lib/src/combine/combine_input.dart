// lib/src/combine/combine_input.dart

/// One item being combined, described only by what [CombineResolver]
/// needs to check eligibility: a key identifying "the same thing" (e.g.
/// an `ItemInstance.definitionId`) and a numeric tier (e.g. its
/// `itemClass`). Core-generic — has no idea these came from an item.
class CombineInput {
  const CombineInput({required this.matchKey, required this.tier});

  final String matchKey;
  final int tier;
}
