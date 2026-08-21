/// A handle to a single [EventBus.subscribe] registration. Call [cancel] to
/// stop receiving events on this subscription.
class EventSubscription {
  EventSubscription._(this._cancel);

  final void Function() _cancel;

  /// Stops this subscription's handler from being called for future events.
  void cancel() => _cancel();
}

/// A typed publish/subscribe event bus. Dispatch is by exact runtime type of
/// the published event — a handler registered via `subscribe<Foo>` is only
/// ever called for events whose runtime type is exactly `Foo`.
///
/// When subscribing, give the handler an explicitly-typed parameter (e.g.
/// `bus.subscribe((FooEvent e) => ...)`) or pass the type argument
/// explicitly (`bus.subscribe<FooEvent>(...)`) — an untyped closure parameter
/// infers as `dynamic` and will not match published events correctly.
class EventBus {
  final Map<Type, List<void Function(Object?)>> _handlers = {};

  /// Registers [handler] to be called for every event published with
  /// [publish] whose runtime type is exactly `T`. Returns a subscription
  /// that can be [EventSubscription.cancel]ed.
  EventSubscription subscribe<T>(void Function(T event) handler) {
    void wrapped(Object? event) => handler(event as T);
    final handlers = _handlers.putIfAbsent(T, () => <void Function(Object?)>[]);
    handlers.add(wrapped);
    return EventSubscription._(() => handlers.remove(wrapped));
  }

  /// Like [subscribe], but for callers that only know the event type at
  /// runtime (e.g. a rule engine dispatching on a [Type] value read from
  /// data rather than known at compile time). [handler] receives the
  /// event as `Object`.
  EventSubscription subscribeDynamic(
    Type type,
    void Function(Object event) handler,
  ) {
    final handlers = _handlers.putIfAbsent(type, () => <void Function(Object?)>[]);
    void wrapped(Object? event) => handler(event!);
    handlers.add(wrapped);
    return EventSubscription._(() => handlers.remove(wrapped));
  }

  /// Dispatches [event] to every handler subscribed for its exact runtime
  /// type. No-op if there are no such subscribers.
  void publish<T>(T event) {
    final handlers = _handlers[event.runtimeType];
    if (handlers == null) return;
    for (final handler in List<void Function(Object?)>.from(handlers)) {
      handler(event);
    }
  }
}
