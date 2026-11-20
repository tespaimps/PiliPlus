// Focused cache tests do not call desktop FFI APIs. Skip their native build
// hooks here; production Android builds still use the standard Flutter command.
// This runner targets the Flutter version pinned in pubspec.yaml.
import 'dart:io';

import 'package:flutter_tools/runner.dart' as runner;
import 'package:flutter_tools/src/base/context.dart';
import 'package:flutter_tools/src/base/template.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/commands/test.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/isolated/mustache_template.dart';

Future<void> main() async {
  final configuredRoot = Platform.environment['FLUTTER_ROOT'];
  Cache.flutterRoot = configuredRoot != null && configuredRoot.isNotEmpty
      ? configuredRoot
      : File(Platform.resolvedExecutable)
            .parent
            .parent
            .parent
            .parent
            .parent
            .path;
  exitCode = await runner.run(
    [
      'test',
      '--no-pub',
      '--no-test-assets',
      'test/pages/download/download_owner_test.dart',
      'test/pages/download/download_owner_widget_test.dart',
    ],
    () => [TestCommand()],
    reportCrashes: false,
    overrides: <Type, Generator>{
      TemplateRenderer: () => const MustacheTemplateRenderer(),
    },
    shutdownHooks: globals.shutdownHooks,
  );
}
