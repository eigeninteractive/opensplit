/// How badly a waiting update wants to be installed.
enum UpdateUrgency {
  /// Play is holding nothing, or nothing this build can install.
  none,

  /// Downloads in the background while the app stays usable, and declining
  /// costs nothing. The ordinary case.
  flexible,

  /// A full-screen installation flow. Play can report cancellation or failure.
  immediate,
}
