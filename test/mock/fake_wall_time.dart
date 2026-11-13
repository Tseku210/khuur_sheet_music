import 'package:flutter_test/flutter_test.dart';

/// The wall time a `ScorePlayer` under test reads. It follows the test
/// binding's clock, which `tester.pump` advances together with the timers.
final class FakeWallTime {
  FakeWallTime(this._binding) : _start = _binding.clock.now();

  final TestWidgetsFlutterBinding _binding;
  final DateTime _start;

  /// How far this time runs ahead of the timers. A test adds to it to model
  /// an isolate that was busy while a timer was due, so the timer fires
  /// late.
  Duration stalled = Duration.zero;

  Duration now() => _binding.clock.now().difference(_start) + stalled;
}
