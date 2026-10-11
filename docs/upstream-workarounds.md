# Upstream workaround review

Reviewed on 2026-10-11 while consolidating the open dependency updates.
The review covered source and configuration comments, generation options,
release notes and relevant upstream implementations.

| Comment or workaround | Upstream status | Action in this batch |
| --- | --- | --- |
| OPFS nested transactions, `lib/data/sync/outbox_queue.dart` | Drift **2.35.2** fixes the nested-transaction regression introduced in 2.34.3. Main locked 2.35.1. | Upgrade the runtime and its released browser worker. Keep `enqueueInTransaction`: explicit transaction ownership still ensures the local write and outbox row commit together. Update the historical comment. |
| Generic synchronous Drizzle transactions, `server/src/do/group/index.ts` | Both **1.0.0-rc.4** and PR #13's **1.0.0-rc.5-5935859** reject a return type they cannot prove is synchronous. Their SQLite transaction declarations retain the conditional Promise check. | Keep the boxed return value and rc.4. The proposed prerelease does not remove this typing constraint. |
| Plugin diagnostics cannot be ignored, `analysis_options.yaml` | Dart SDK issue **#62131** is closed. Plugin diagnostics use qualified names such as `riverpod_lint/scoped_providers_should_specify_dependencies`. | Correct the stale comment. Verify the warning appears without an ignore and disappears with a qualified ignore on Dart 3.13.3. Keep the existing project-wide rule decision; the test harness still triggers its syntactic scoping check. |
| A component first used as nullable becomes nullable globally, `server/src/app.ts` | Reproduced against the installed **@hono/zod-openapi 1.6.3 / zod-to-openapi 9.1.0**. The latter is the latest published version reviewed. | Keep explicit non-null component registration before nullable use. |
| Flattened union payloads, `server/src/schemas/identity.ts` and `docs/architecture.md` | OpenAPI Generator **7.26.0** is available beyond the pinned 7.25.0. Its Dart fixes include enum collections and query parameters, but no verified fix for this app's union models with the JSON serializer. Dart-Dio's feature table also covers its default built_value serializer. | Keep the wire shapes and generator pin. Qualify the comments to refer to the selected serializer rather than every Dart generator. |
| Optional versus null fields, `docs/architecture.md` | The pinned generator already offers **useOptional**, which generates an `Optional<T>` wrapper. The current configuration does not enable it. | Correct the blanket limitation in the documentation. Whole-row PUTs remain an intentional contract; enabling wrappers would require a separate API/client review. |

## Evidence

- Drift's [2.35.2 changelog](https://pub.dev/packages/drift/changelog#2352)
  and [matching release assets](https://github.com/simolus3/drift/releases/tag/drift-2.35.2).
  Only the runtime has a 2.35.2 release; `drift_dev` stays on 2.35.1.
- Drizzle's [published rc.4 transaction declaration](https://unpkg.com/drizzle-orm@1.0.0-rc.4/sqlite-core/async/db.d.ts)
  and the `sqlite-core/async/db.d.ts` and `durable-sqlite/session.d.ts` files
  in both published package archives. The existing boxed value is a typing
  adaptation, not evidence of a database migration or async runtime defect.
- Dart's [plugin-ignore issue](https://github.com/dart-lang/sdk/issues/62131)
  and [qualified-ignore documentation](https://github.com/dart-lang/sdk/blob/main/pkg/analysis_server_plugin/doc/using_plugins.md).
- The [zod-to-openapi generator](https://github.com/asteasolutions/zod-to-openapi):
  registering `Envelope { value: Probe.nullable() }` before `Probe` emits
  `Probe.nullable: true`; reversing the registration order preserves its
  non-null schema and makes only the envelope property nullable.
- OpenAPI Generator's [7.26.0 release](https://github.com/OpenAPITools/openapi-generator/releases/tag/v7.26.0),
  [Dart-Dio options](https://openapi-generator.tech/docs/generators/dart-dio/),
  and [pinned optional wrapper](https://github.com/OpenAPITools/openapi-generator/blob/v7.25.0/modules/openapi-generator/src/main/resources/dart/libraries/dio/optional.mustache).
  Its enum-collection fix does not affect the current contract, which has
  no arrays of enum values. A newer generator alone is not grounds to remove
  the existing union handling.

## Boundaries that remain useful

Several comments describe platform or architecture constraints rather than
upstream defects that a dependency bump would remove:

- `build.yaml`: FTS5 must be enabled for Drift's SQL parser, and the
  `not_shared` builder lets other generators resolve the generated row types.
- `lib/data/local/database.dart`: the Android background Flutter engine uses
  a separate database connection. `PRAGMA data_version` detects its commits.
- `web/flutter_bootstrap.js`: Flutter's retired service worker does not
  provide this app's offline cache or push handling; Workbox supplies both.
- `tool/brand_icons.dart`: the favicon needs transparent source artwork,
  while native launcher icons use an opaque source.
- `tool/openapi_dart.yaml`: calendar dates stay date strings at the wire
  boundary; unknown enum values use a read-side sentinel for forward
  compatibility. Neither changes into a safe default through a routine bump.
- `server/src/chunked.ts`: bounded SQL parameter batches respect the database
  platform's limits and remain safe when the ORM changes.
- `android/gradle.properties`: the release build still warns that
  `firebase_core` 4.15.0 and `in_app_review` 2.0.12 apply the legacy Kotlin
  Gradle plugin. These are their current published releases. Keep
  `android.builtInKotlin=false` until both plugins migrate; Flutter's
  [migration guide](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin)
  describes this as temporary AGP 9 compatibility. Removing it is a separate
  toolchain task, not part of these native plugin patches.

The notification prerelease, its Android toolchain requirements, and the
coupled connectivity update remain deferred. The separate Drizzle prerelease
also remains deferred, as explicitly agreed.
