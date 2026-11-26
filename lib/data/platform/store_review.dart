import 'package:in_app_review/in_app_review.dart';

/// Whether Play offers the in-app review flow.
Future<bool> isStoreReviewAvailable() => InAppReview.instance.isAvailable();

/// Ask Play to show the in-app review flow.
Future<void> requestStoreReview() => InAppReview.instance.requestReview();
