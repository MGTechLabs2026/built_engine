// lib/src/combine/combine_exceptions.dart
import 'combine_input.dart';

/// Thrown by [CombineResolver.resolve] when the given [CombineInput]s
/// don't all share the same `matchKey`/`tier` — Combine requires every
/// input to be "the same thing, at the same tier."
class CombineMismatchException implements Exception {
  const CombineMismatchException(this.first, this.mismatched);

  final CombineInput first;
  final CombineInput mismatched;

  @override
  String toString() =>
      'CombineMismatchException: expected matchKey="${first.matchKey}" '
      'tier=${first.tier}, got matchKey="${mismatched.matchKey}" '
      'tier=${mismatched.tier}';
}
