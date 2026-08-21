import 'dart:math';

/// The sole sanctioned source of randomness in this package. Gameplay
/// systems (conditions, effects, rules) must never call `dart:math`'s
/// `Random` directly — everything goes through an injected [RngService]
/// instance, so a run is reproducible from its seed.
class RngService {
  RngService(int seed) : _random = Random(seed);

  final Random _random;

  /// A pseudo-random double in `[0.0, 1.0)`.
  double nextDouble() => _random.nextDouble();

  /// A pseudo-random integer in `[0, max)`.
  int nextInt(int max) => _random.nextInt(max);

  /// Whether a random draw falls within [probability] (`0.0`-`1.0`).
  /// `probability <= 0.0` never returns true; `probability >= 1.0` always
  /// does.
  bool chance(double probability) => _random.nextDouble() < probability;
}
