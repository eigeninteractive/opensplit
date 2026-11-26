/// This build has no in-app store review flow.
Future<bool> isStoreReviewAvailable() async => false;

/// No store review action is available.
Future<void> requestStoreReview() async {}
