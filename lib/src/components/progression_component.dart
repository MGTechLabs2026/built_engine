/// An entity's accumulated progress toward arbitrary named subjects (e.g.
/// a content plugin's own "item:brass_knuckles" mastery or
/// "technique:jab" tier). The engine never hardcodes a subject name.
///
/// A distinct component from [ResourceComponent] even though its shape is
/// similar — progression has its own tier/threshold semantics (see
/// [ProgressionEngine]) and its own namespace, so a "stamina" resource and
/// a "stamina" progression subject can never collide.
class ProgressionComponent {
  ProgressionComponent(Map<String, num> experience)
      : experience = Map.unmodifiable(experience);

  final Map<String, num> experience;
}
