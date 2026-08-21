import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('plugin exceptions', () {
    test('DuplicatePluginException message names the plugin', () {
      final exception = DuplicatePluginException('combat');
      expect(exception, isA<PluginSystemException>());
      expect(exception.toString(), contains('combat'));
    });

    test('MissingPluginDependencyException names both plugins', () {
      final exception =
          MissingPluginDependencyException('combat', 'container');
      expect(exception.toString(), contains('combat'));
      expect(exception.toString(), contains('container'));
    });

    test('CyclicPluginDependencyException names every plugin in the cycle',
        () {
      final exception =
          CyclicPluginDependencyException(['a', 'b', 'a']);
      expect(exception.toString(), contains('a'));
      expect(exception.toString(), contains('b'));
    });
  });
}
