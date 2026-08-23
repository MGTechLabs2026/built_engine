/// Base type for every exception thrown by the content registry
/// (`lib/src/content/`).
abstract class ContentSystemException implements Exception {
  const ContentSystemException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thrown by a content factory (effect/condition) when a required
/// parameter is missing or has the wrong type. [path] names the field
/// (e.g. `'amount'`, or `'components.cost.resource'` once a caller has
/// prefixed it with where the field lives); [problem] describes what's
/// wrong. [ContentRegistry] catches this at the top level of a
/// definition and re-throws [ContentValidationException] naming which
/// definition it came from.
class ContentFieldException extends ContentSystemException {
  ContentFieldException(this.path, this.problem) : super('$path — $problem');

  final String path;
  final String problem;
}

/// Thrown by `load`/`loadAll`/`loadRule` when a definition's fields fail
/// validation — wraps the underlying [ContentFieldException] with which
/// definition it came from.
class ContentValidationException extends ContentSystemException {
  ContentValidationException(String definitionId, ContentFieldException cause)
      : super("Invalid content '$definitionId': $cause");
}

/// Thrown when a content or rule id is registered more than once. Ids
/// are globally unique across every content type and every rule.
class ContentDuplicateIdException extends ContentSystemException {
  ContentDuplicateIdException(String id)
      : super('Content id already registered: $id');
}

/// Thrown when a definition's `requires` names an id that isn't
/// registered — neither already in the registry, nor elsewhere in the
/// same `loadAll` batch.
class ContentDependencyException extends ContentSystemException {
  ContentDependencyException(String definitionId, String missingRequiredId)
      : super(
          "Content '$definitionId' requires unknown content "
          "'$missingRequiredId'",
        );
}

/// Thrown by [ContentRegistry.get]/[ContentRegistry.rule] when no
/// definition with the given id is registered.
class ContentNotFoundException extends ContentSystemException {
  ContentNotFoundException(String id)
      : super('No content registered with id: $id');
}

/// Thrown when an effect/condition/trigger JSON `"type"` key has no
/// registered factory. [kind] is `'effect'`, `'condition'`, or
/// `'trigger'`.
class UnknownContentFactoryException extends ContentSystemException {
  UnknownContentFactoryException(String kind, String key)
      : super('No $kind factory registered for type: $key');
}
