import 'package:flutter/foundation.dart';
import 'package:inappify_sdk/src/platform/contracts/sdk_failure.dart';
import 'package:inappify_sdk/src/platform/contracts/sdk_snapshot.dart';

/// Result of a semantic SDK operation.
///
/// A successful result has no [failure]. A failed result always has a
/// [failure]. Semantic platform operations must include [snapshot] on success;
/// failures may include it when the backend has authoritative state to mirror.
/// The coordinator rejects a successful platform result without a snapshot.
@immutable
class InappifySdkResult<T> {
  const InappifySdkResult._({this.data, this.snapshot, this.failure});

  final T? data;
  final InappifySdkSnapshot? snapshot;
  final InappifyFailure? failure;

  bool get isSuccess => failure == null;

  factory InappifySdkResult.success({T? data, InappifySdkSnapshot? snapshot}) {
    return InappifySdkResult<T>._(data: data, snapshot: snapshot);
  }

  factory InappifySdkResult.failure(
    InappifyFailure failure, {
    InappifySdkSnapshot? snapshot,
  }) {
    return InappifySdkResult<T>._(failure: failure, snapshot: snapshot);
  }
}
