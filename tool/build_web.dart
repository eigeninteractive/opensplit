// Builds the production web bundle, including the service worker that serves
// the client offline and receives web push.
//
// The bundle is two things in one tree. `site/` is plain static HTML — the
// landing page, the privacy policy, the terms — and it is served from the host
// root, where it needs no engine, no session and no JavaScript to be readable
// by a person, a crawler or an OAuth reviewer. The Flutter client is built
// underneath it at `/app/`.
//
// --base-href is what keeps the Dart side unaware of the split: Flutter's path
// URL strategy resolves routes after the base, so go_router still sees
// `/g/123` while the browser shows `/app/g/123`, and no route constant moves.
//
// `build/web` is also the Worker's `assets.directory`, so this is what stands
// between a deploy and an empty origin: one command produces the whole front
// end, and `wrangler deploy` uploads it alongside the script as one version.

import 'dart:io';

import 'package:args/args.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('config', defaultsTo: 'env/app.json')
    ..addOption(
      'build-number',
      help:
          "The release's build number, which About shows. The release "
          'workflow passes the one the Android bundle gets.',
    )
    ..addFlag(
      'site-only',
      negatable: false,
      help:
          'Build only the static root, skipping the Flutter client. Seconds '
          'rather than minutes, and needs no Flutter toolchain.',
    )
    ..addFlag('help', abbr: 'h', negatable: false);
  try {
    final options = parser.parse(args);
    if (options.rest.isNotEmpty) {
      throw FormatException('Unexpected arguments: ${options.rest.join(' ')}');
    }
    if (options.flag('help')) {
      stdout.writeln('Build the static site and Flutter /app bundle.');
      stdout.writeln(parser.usage);
      return;
    }
    await _build(
      options.option('config')!,
      buildNumber: _buildNumber(options.option('build-number')),
      siteOnly: options.flag('site-only'),
    );
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(parser.usage);
    exitCode = 64;
  } catch (error) {
    stderr.writeln('Web build failed: $error');
    exitCode = 1;
  }
}

/// Builds `build/web`, which is both the deployable bundle and the Worker's
/// assets directory.
///
/// [siteOnly] leaves out the Flutter client. That mode exists because the
/// Worker cannot start without an assets directory — `wrangler dev` refuses
/// outright — and requiring a two-minute Flutter build before anyone can run
/// the server would be a strange price for editing a route handler. What it
/// produces is not a stub: the static root and `_headers` are exactly what
/// ships, so the part of the serving layer that lives in that file can be
/// tested against a real Worker. Only `/app/` is missing, and a request for it
/// answers 404 rather than pretending.
Future<void> _build(
  String configPath, {
  int? buildNumber,
  bool siteOnly = false,
}) async {
  if (!siteOnly) {
    await _run('dart', [
      'run',
      'tool/verify_config.dart',
      '--config=$configPath',
    ]);
  }
  // Cleared wholesale rather than letting the Flutter build clear its own
  // output: it only owns build/web/app, so a file left at the root by an
  // earlier layout would survive and outrank the page meant to be there.
  final output = Directory('build/web');
  if (output.existsSync()) output.deleteSync(recursive: true);

  if (!siteOnly) {
    await _run('flutter', [
      'build',
      'web',
      '--wasm',
      '--no-web-resources-cdn',
      '--release',
      '--base-href=/app/',
      // Absolute, which is what --output requires.
      '--output=${Directory.current.path}/build/web/app',
      '--dart-define-from-file=$configPath',
      // Into version.json, which is where package_info_plus reads it on the
      // web. Without it a release would show pubspec.yaml's version alone.
      if (buildNumber != null) '--build-number=$buildNumber',
    ]);
  }

  _copyInto(Directory('site'), output);
  // The faces the app bundles, served to the static pages from this origin
  // (see site/site.css) rather than fetched from Google for every visitor. The
  // licence goes with them, as the OFL asks.
  _copyInto(
    Directory('assets/google_fonts'),
    Directory('${output.path}/fonts'),
  );
  _checkServingRules(output);

  if (siteOnly) {
    stdout.writeln('Static root only — no Flutter client in this bundle.');
    stdout.writeln('  /      static site from site/');
    stdout.writeln('  /app/  MISSING. Do not deploy this.');
    return;
  }

  // Last, because it precaches the finished client, icons included.
  await _buildServiceWorker(output, configPath);

  stdout.writeln('Production web bundle ready.');
  stdout.writeln('  /      static site from site/');
  stdout.writeln('  /app/  Flutter client');
}

/// Fails if the file that configures response headers did not reach the bundle.
///
/// Cloudflare parses `_headers` from the root of the assets directory and never
/// serves it, which means its absence produces no 404 and no error anywhere —
/// the site simply comes back without cross-origin isolation, and the client's
/// database stops working in a way that looks like a Flutter bug. It is copied
/// from `site/`, so the way to lose it is a copy that skips names beginning
/// with an underscore.
void _checkServingRules(Directory output) {
  if (!File('${output.path}/_headers').existsSync()) {
    throw StateError(
      '_headers did not reach ${output.path}. Cloudflare reads it from the '
      'root of the assets directory, and its absence is silent.',
    );
  }
}

/// Builds `/app/sw.js` with Workbox from `service_worker/`.
///
/// That package precaches the release and bundles the worker with Firebase's
/// public identifiers from [configPath]; see `service_worker/build.ts`. Its
/// install is part of the build, so a fresh checkout needs nothing beyond pnpm.
Future<void> _buildServiceWorker(Directory output, String configPath) async {
  const package = 'service_worker';
  await _run('pnpm', ['--dir', package, 'install', '--frozen-lockfile']);
  await _run('pnpm', [
    '--dir',
    package,
    'run',
    'build',
    '--root=${output.absolute.path}',
    '--config=${File(configPath).absolute.path}',
  ]);
}

/// Copies [from] over [to], including dotfiles.
///
/// `.well-known/assetlinks.json` is a dotfile directory and is what makes
/// Android App Links verify, so a copy that quietly skips it fails in the way
/// that is hardest to notice: links keep working, they just open a browser.
void _copyInto(Directory from, Directory to) {
  for (final entity in from.listSync(recursive: true)) {
    final relative = entity.path.substring(from.path.length + 1);
    final target = '${to.path}/$relative';
    if (entity is Directory) {
      Directory(target).createSync(recursive: true);
    } else if (entity is File) {
      Directory(File(target).parent.path).createSync(recursive: true);
      entity.copySync(target);
    }
  }
}

int? _buildNumber(String? value) {
  if (value == null) return null;
  final number = int.tryParse(value);
  if (number == null || number < 1) {
    throw FormatException('Invalid build number: $value');
  }
  return number;
}

Future<void> _run(String executable, List<String> arguments) async {
  final process = await Process.start(
    executable,
    arguments,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) exit(code);
}
