import 'technique_descriptor.dart';

/// Pure. Sums every descriptor's `axes` map. **Descriptors only** — no
/// style, no base (rule 2). Mirrors `BuildResolver` / `ModifierResolver`'s
/// "function, no storage" shape.
class TechniqueVariantResolver {
  const TechniqueVariantResolver();

  Map<String, num> resolve(Iterable<TechniqueDescriptor> descriptors) {
    final profile = <String, num>{};
    for (final d in descriptors) {
      d.axes.forEach((axis, mag) {
        profile[axis] = (profile[axis] ?? 0) + mag;
      });
    }
    return profile;
  }
}

/// Pure. `base ⊕ contribution`, per axis, additive. The one place style
/// seed / centre meets the descriptor profile — kept out of the resolver
/// (rule 3). `mintTechniqueVariant` calls
/// `composeAxisProfile(styleCentre, resolver.resolve(descriptors))`.
Map<String, num> composeAxisProfile(
  Map<String, num> base,
  Map<String, num> contribution,
) {
  final out = <String, num>{...base};
  contribution.forEach((axis, value) {
    out[axis] = (out[axis] ?? 0) + value;
  });
  return out;
}
