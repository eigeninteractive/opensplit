/// Android updates through Play (see `AppUpdateService`), so this never fires.
void watchForNewRelease(void Function() onReady) {}

/// Never called off the web, where [watchForNewRelease] never fires.
void restartIntoNewRelease() {}
