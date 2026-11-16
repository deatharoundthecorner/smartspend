/// Stable errors for presentation. Storage failures retain their original cause.
class AppException implements Exception {
  const AppException(this.code, this.message, [this.cause]);
  final String code;
  final String message;
  final Object? cause;
  @override
  String toString() => '$code: $message';
}

class ValidationException extends AppException {
  const ValidationException(String message) : super('validation', message);
}

class NotFoundException extends AppException {
  const NotFoundException(String message) : super('not_found', message);
}

class ConflictException extends AppException {
  const ConflictException(String message) : super('conflict', message);
}
