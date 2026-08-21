import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

class _Ping {
  const _Ping(this.n);
  final int n;
}

class _Pong {
  const _Pong(this.n);
  final int n;
}

void main() {
  group('EventBus', () {
    test('a subscriber receives a published event of its type', () {
      final bus = EventBus();
      final received = <int>[];

      bus.subscribe<_Ping>((event) => received.add(event.n));
      bus.publish(const _Ping(1));

      expect(received, equals([1]));
    });

    test('multiple subscribers to the same type all receive the event', () {
      final bus = EventBus();
      final receivedA = <int>[];
      final receivedB = <int>[];

      bus.subscribe<_Ping>((event) => receivedA.add(event.n));
      bus.subscribe<_Ping>((event) => receivedB.add(event.n));
      bus.publish(const _Ping(5));

      expect(receivedA, equals([5]));
      expect(receivedB, equals([5]));
    });

    test('a subscriber never receives events of a different type', () {
      final bus = EventBus();
      final pings = <int>[];
      final pongs = <int>[];

      bus.subscribe<_Ping>((event) => pings.add(event.n));
      bus.subscribe<_Pong>((event) => pongs.add(event.n));

      bus.publish(const _Ping(1));
      bus.publish(const _Pong(2));

      expect(pings, equals([1]));
      expect(pongs, equals([2]));
    });

    test('publishing with no subscribers does not throw', () {
      final bus = EventBus();
      expect(() => bus.publish(const _Ping(1)), returnsNormally);
    });

    test('a cancelled subscription stops receiving events', () {
      final bus = EventBus();
      final received = <int>[];

      final subscription = bus.subscribe<_Ping>((event) => received.add(event.n));
      subscription.cancel();
      bus.publish(const _Ping(1));

      expect(received, isEmpty);
    });

    test('publishing through a statically-widened type still dispatches', () {
      final bus = EventBus();
      final received = <int>[];
      bus.subscribe<_Ping>((event) => received.add(event.n));

      final Object widened = const _Ping(1);
      bus.publish(widened);

      expect(received, equals([1]));
    });

    test('cancelling one of two subscribers to the same type leaves the other active', () {
      final bus = EventBus();
      final receivedA = <int>[];
      final receivedB = <int>[];

      final subscriptionA = bus.subscribe<_Ping>((event) => receivedA.add(event.n));
      bus.subscribe<_Ping>((event) => receivedB.add(event.n));
      subscriptionA.cancel();
      bus.publish(const _Ping(1));

      expect(receivedA, isEmpty);
      expect(receivedB, equals([1]));
    });

    test('subscribeDynamic dispatches by a Type known only at runtime', () {
      final bus = EventBus();
      final received = <int>[];
      bus.subscribeDynamic(_Ping, (event) => received.add((event as _Ping).n));

      bus.publish(const _Ping(7));

      expect(received, equals([7]));
    });

    test('subscribeDynamic subscription can be cancelled', () {
      final bus = EventBus();
      final received = <int>[];
      final subscription =
          bus.subscribeDynamic(_Ping, (event) => received.add((event as _Ping).n));

      subscription.cancel();
      bus.publish(const _Ping(1));

      expect(received, isEmpty);
    });

    test('subscribeDynamic does not receive events of a different type', () {
      final bus = EventBus();
      final pings = <int>[];
      bus.subscribeDynamic(_Ping, (event) => pings.add((event as _Ping).n));

      bus.publish(const _Pong(1));

      expect(pings, isEmpty);
    });
  });
}
