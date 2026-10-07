import 'app_failure.dart';

sealed class AppResult<T> {
  const AppResult();

  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(AppFailure failure) onFailure,
  });
}

final class Success<T> extends AppResult<T> {
  const Success(this.value);

  final T value;

  @override
  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(AppFailure failure) onFailure,
  }) => onSuccess(value);
}

final class FailureResult<T> extends AppResult<T> {
  const FailureResult(this.failure);

  final AppFailure failure;

  @override
  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(AppFailure failure) onFailure,
  }) => onFailure(failure);
}
