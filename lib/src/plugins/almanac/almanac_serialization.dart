/// Almanac v1 — persisted serialization envelope.
///
/// [AlmanacState] serializes only its seven record lists (§8.1). This layer
/// is the single place that stamps and verifies the on-disk schema version:
/// `stateToJson` wraps the model map with `almanacSchemaVersion`, and
/// `stateFromJson` checks that key *first* and fails loud on a mismatch — the
/// migration seam. It imports the model file and `dart:convert` only; file IO
/// lives one layer down in the repository (Task 3).
library;

import 'dart:convert';

import 'almanac_models.dart';

/// Raised when a decoded Almanac payload declares a schema version this build
/// does not understand. Fail-loud: no migration, no coercion, no recovery.
class AlmanacSchemaVersionError implements Exception {
  AlmanacSchemaVersionError(this.found, this.expected);

  /// The `almanacSchemaVersion` value read from the payload — `null` when the
  /// key was absent.
  final Object? found;

  /// The only version this build accepts.
  final int expected;

  @override
  String toString() =>
      'Almanac schema version $found is not supported (expected $expected)';
}

/// Stateless namespace owning the Almanac version envelope, applied exactly
/// once. `stateToJson` / `encode` add the version key; `stateFromJson` /
/// `decode` require it to equal [schemaVersion].
abstract final class AlmanacSerialization {
  /// The persisted envelope version — kept in step with
  /// [AlmanacState.almanacSchemaVersion].
  static const int schemaVersion = 1;

  /// `{ 'almanacSchemaVersion': 1, 'runs': [...], 'builds': [...], ... }` —
  /// the model's seven lists with the version key prepended by this layer.
  static Map<String, dynamic> stateToJson(AlmanacState state) => {
    'almanacSchemaVersion': schemaVersion,
    ...state.toJson(),
  };

  /// Reads `almanacSchemaVersion` before anything else: a value that is not
  /// [schemaVersion] — a missing key reads as `null` — raises
  /// [AlmanacSchemaVersionError]. The envelope key left in [json] is harmless;
  /// [AlmanacState.fromJson] ignores unknown keys.
  static AlmanacState stateFromJson(Map<String, dynamic> json) {
    final found = json['almanacSchemaVersion'];
    if (found != schemaVersion) {
      throw AlmanacSchemaVersionError(found, schemaVersion);
    }
    return AlmanacState.fromJson(json);
  }

  /// `jsonEncode(stateToJson(state))`.
  static String encode(AlmanacState state) => jsonEncode(stateToJson(state));

  /// `stateFromJson(jsonDecode(text) as Map<String, dynamic>)`. Malformed JSON
  /// (a `FormatException` from `jsonDecode`) and a non-object top level (the
  /// cast fails) both propagate unchanged.
  static AlmanacState decode(String text) =>
      stateFromJson(jsonDecode(text) as Map<String, dynamic>);
}
