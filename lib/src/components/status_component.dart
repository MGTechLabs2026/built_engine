/// An entity's currently-active status-effect names. No duration or
/// stacking is modeled here — that belongs to a future Scheduler/Modifier
/// pass; this is a plain set of "is this status currently active" flags.
class StatusComponent {
  StatusComponent(Set<String> activeStatuses)
      : activeStatuses = Set.unmodifiable(activeStatuses);

  final Set<String> activeStatuses;
}
