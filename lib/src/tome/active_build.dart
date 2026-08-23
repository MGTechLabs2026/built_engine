import '../entity/entity_id.dart';
import 'build_component_ref.dart';

/// A snapshot of what an owner's Tome currently resolves to — the *only*
/// interface future Combat is meant to consume. Deliberately flat (no
/// slot/size/rotation): Combat cares what is active, never where it sits
/// in the Tome, so Combat never needs to inspect the Tome itself.
class ActiveBuild {
  const ActiveBuild({required this.owner, required this.components});

  final EntityId owner;
  final List<BuildComponentRef> components;
}
