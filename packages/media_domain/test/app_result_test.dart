import 'package:media_domain/media_domain.dart';
import 'package:test/test.dart';

void main() {
  test('success fold invokes only the success branch', () {
    const result = Success<int>(7);
    var failureCalled = false;

    final value = result.fold(
      onSuccess: (value) => value * 2,
      onFailure: (failure) {
        failureCalled = true;
        return -1;
      },
    );

    expect(value, 14);
    expect(failureCalled, isFalse);
  });

  test('failure preserves a safe stable code and retryability', () {
    const failure = AppFailure(
      code: 'ROOT_PERMISSION_REVOKED',
      messageKey: 'rootPermissionRevoked',
      retryable: true,
      safeDetail: 'Persisted read grant is absent.',
    );
    const result = FailureResult<int>(failure);

    expect(result.failure.code, 'ROOT_PERMISSION_REVOKED');
    expect(result.failure.retryable, isTrue);
  });

  test('cancellation controller notifies once and stays cancelled', () async {
    final controller = CancellationController();
    var notifications = 0;
    final notification = controller.token.whenCancelled.then(
      (_) => notifications++,
    );

    controller.cancel();
    controller.cancel();
    await notification;

    expect(controller.token.isCancelled, isTrue);
    expect(notifications, 1);
  });
}
