// lib/src/combine/combine_input.dart

/// One entity being combined, described only by what [CombineResolver]
/// needs to check eligibility: a key identifying "the same thing" and a
/// numeric tier (e.g. a class or rank). Core-generic — has no idea what
/// these values represent in any particular content domain.
class CombineInput {
  const CombineInput({required this.matchKey, required this.tier});

  final String matchKey;
  final int tier;
}
