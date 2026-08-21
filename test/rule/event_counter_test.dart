import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

class _Ping {
  const _Ping();
}

class _Pong {
  const _Pong();
}

void main() {
  group('EventCounter', () {
    test('counts occurrences of a tracked event type', () {
      final events = EventBus();
      final counter = EventCounter(events);
      counter.trackType(_Ping);

      events.publish(const _Ping());
      events.publish(const _Ping());

      expect(counter.countOfType(_Ping), equals(2));
    });

    test('does not count a type that was never tracked', () {
      final events = EventBus();
      final counter = EventCounter(events);

      events.publish(const _Ping());

      expect(counter.countOfType(_Ping), equals(0));
    });

    test('tracking one type does not count a different type', () {
      final events = EventBus();
      final counter = EventCounter(events);
      counter.trackType(_Ping);

      events.publish(const _Pong());

      expect(counter.countOfType(_Ping), equals(0));
      expect(counter.countOfType(_Pong), equals(0));
    });

    test('counting starts from zero, not retroactively', () {
      final events = EventBus();
      final counter = EventCounter(events);

      events.publish(const _Ping());
      counter.trackType(_Ping);
      events.publish(const _Ping());

      expect(counter.countOfType(_Ping), equals(1));
    });

    test('calling trackType twice does not reset the count', () {
      final events = EventBus();
      final counter = EventCounter(events);
      counter.trackType(_Ping);
      events.publish(const _Ping());
      counter.trackType(_Ping);

      expect(counter.countOfType(_Ping), equals(1));
    });
  });
}
