final class AppFailure {
  const AppFailure({
    required this.code,
    required this.messageKey,
    required this.retryable,
    this.safeDetail,
  });

  final String code;
  final String messageKey;
  final bool retryable;
  final String? safeDetail;
}
