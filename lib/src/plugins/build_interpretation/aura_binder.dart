import 'package:build_engine/build_engine.dart';

import 'build_action_interpreter.dart';

/// Registers the [AuraRule]s of every hung component with the
/// [RuleEngine] for the duration of one resolved build (in the headless
/// harness: one fight), and hands back an [AuraBinding] that detaches
/// them again.
///
/// Stateless (`const`). Each [bind] call produces a self-contained
/// [AuraBinding] tied to exactly the `build.owner` and `opponents` passed
/// at that call — there is no in-place update path. When the build
/// changes, the flow is always: dispose the old binding, resolve the new
/// build, `bind` again.
///
/// This class imports no Combat symbol and reads no `TurnStarted` /
/// `ActionCompleted` field. The one Combat-shaped fact it uses — "the
/// aura rule's `subjectOf` yields the acting entity" — is the
/// content-trigger-registry contract, wired by `CombatPlugin` (see the
/// SP2 spec §5.5/§5.6). Opponents are passed in by the caller, not
/// derived from combat state.
///
/// An aura whose trigger descriptor has no `subjectOf` is still
/// registered, but never fires: with a null subject/actor both the
/// self-scope `SubjectIs(owner)` guard and the opponent-scope event-actor
/// guard evaluate `false`.
class AuraBinder {
  const AuraBinder();

  AuraBinding bind({
    required ResolvedBuild build,
    required BuildActionInterpreter interpreter,
    required PluginContext context,
    List<EntityId> opponents = const [],
  }) {
    final subscriptions = <EventSubscription>[];
    try {
      for (final aura in interpreter.auraRules(build: build, context: context)) {
        final wired = _wire(aura, owner: build.owner, opponents: opponents);
        if (wired == null) continue; // opponent-scope aura, no opponent -> inert
        subscriptions.add(context.rules.register(wired));
      }
    } catch (_) {
      // `register` makes each subscription live immediately, and a throw
      // from a *later* `_wire` means the caller never receives an
      // `AuraBinding` to dispose. Detach what is already live before the
      // failure escapes, so a failed `bind` leaves no aura attached
      // (spec §5.4: "safe to dispose from any path").
      for (final subscription in subscriptions) {
        subscription.cancel();
      }
      rethrow;
    }
    return AuraBinding(subscriptions);
  }

  /// Builds the concrete [Rule] handed to `RuleEngine.register`, scoping
  /// it to owner/opponent. Returns `null` for an opponent-scope aura when
  /// there is no opponent. Throws [ArgumentError] for an opponent-scope
  /// aura with more than one opponent (SP2 is strictly 1-v-1; a
  /// multi-enemy mode must define its own opponent-selection policy).
  Rule? _wire(
    AuraRule aura, {
    required EntityId owner,
    required List<EntityId> opponents,
  }) {
    final body = aura.rule;
    switch (aura.scope) {
      case AuraScope.self:
        // Keep the trigger's own subjectOf (subject = the event's actor);
        // the SubjectIs guard limits firing to the owner's own turn, and
        // the effects then act on that subject (== owner).
        return Rule(
          trigger: body.trigger,
          subjectOf: body.subjectOf,
          conditions: [SubjectIs(owner), ...body.conditions],
          effects: body.effects,
        );
      case AuraScope.opponent:
        if (opponents.isEmpty) return null;
        if (opponents.length > 1) {
          throw ArgumentError.value(
            opponents.length,
            'opponents',
            'opponent-scope auras require exactly one opponent in SP2',
          );
        }
        final opponent = opponents.single;
        return Rule(
          trigger: body.trigger,
          subjectOf: (_) => opponent, // effects land on the opponent
          conditions: [_EventActorIs(body.subjectOf, owner), ...body.conditions],
          effects: body.effects,
        );
    }
  }
}

/// A live set of aura subscriptions. Membership is fixed at construction;
/// [dispose] detaches every one and is safe to call more than once (and
/// on an empty binding).
class AuraBinding {
  AuraBinding(this._subscriptions);

  final List<EventSubscription> _subscriptions;
  var _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
  }
}

/// Passes only when the triggering event's own actor — resolved through
/// [_actorOf], which is the aura rule's trigger-descriptor `subjectOf` —
/// is [_expected]. Event-shape agnostic: it never names a concrete event
/// type. Used by `AuraBinder._wire` for the opponent-scope "on the
/// owner's turn/action" guard.
class _EventActorIs implements Condition {
  const _EventActorIs(this._actorOf, this._expected);

  final EntityId? Function(Object event)? _actorOf;
  final EntityId _expected;

  @override
  bool evaluate(RuleContext context) =>
      _actorOf?.call(context.triggerEvent) == _expected;
}
