import 'package:uuid/uuid.dart';

// ignore: avoid_classes_with_only_static_members
/// A utility class for generating unique IDs.
class IdGenerator {
  const IdGenerator._();
  static const _uuid = Uuid();

  static String generateId(String prefix) {
    return '${prefix}_${_uuid.v4()}';
  }
}
