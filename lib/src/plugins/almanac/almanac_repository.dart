/// Almanac v1 — persistence boundary.
///
/// [AlmanacRepository] is a deliberately whole-state seam (§8.5): `load`
/// returns a *complete* [AlmanacState] (or throws), `save` takes a
/// *complete* [AlmanacState] and writes a *complete* snapshot. There is no
/// incremental / field-level API — no `saveRun`, no `appendFight` — and one
/// must never be added: the recorder owns the whole canonical state in
/// memory and a caller persists it at whatever cadence it likes.
///
/// [InMemoryAlmanacRepository] is the platform-neutral default and lives
/// here. The `dart:io` file-backed implementation is kept one layer down in
/// `almanac_file_repository.dart` (behind the `almanac_file.dart` barrel) so
/// this file — and the neutral `almanac.dart` barrel — stay web-safe.
library;

import 'almanac_models.dart';

/// A whole-state load/save seam over persisted Almanac history. Implementations
/// honour the atomicity contract in §8.5: `load` never surfaces a partial
/// state, `save` never reports a truncated write as success.
abstract interface class AlmanacRepository {
  /// The complete persisted [AlmanacState]. Returns [AlmanacState.empty] when
  /// nothing has been persisted yet; throws on a corrupt or unreadable store.
  AlmanacState load();

  /// Replaces the persisted history with [state] in full.
  void save(AlmanacState state);
}

/// An [AlmanacRepository] that just holds the last saved [AlmanacState] in a
/// field — no serialization, no IO. Before the first `save`, `load` returns
/// the state passed to the constructor (default [AlmanacState.empty]).
class InMemoryAlmanacRepository implements AlmanacRepository {
  InMemoryAlmanacRepository([AlmanacState? initial])
    : _state = initial ?? AlmanacState.empty();

  AlmanacState _state;

  @override
  AlmanacState load() => _state;

  @override
  void save(AlmanacState state) => _state = state;
}
