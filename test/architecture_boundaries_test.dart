@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shared SDK layers do not import transport-specific libraries', () {
    final files = <File>[
      File('lib/inappify_sdk.dart'),
      ..._dartFiles(Directory('lib/models')),
      ..._dartFiles(Directory('lib/src/application')),
      ..._dartFiles(Directory('lib/src/domain')),
      ..._dartFiles(Directory('lib/src/platform/contracts')),
    ];
    const forbiddenImports = <String>[
      "import 'dart:io'",
      'package:web/',
      'package:myket_iap/',
      'package:flutter/services.dart',
      'src/platform/legacy/',
    ];

    for (final file in files) {
      final source = file.readAsStringSync();
      for (final forbiddenImport in forbiddenImports) {
        expect(
          source,
          isNot(contains(forbiddenImport)),
          reason: '${file.path} must not depend on $forbiddenImport.',
        );
      }
    }
  });
}

Iterable<File> _dartFiles(Directory directory) sync* {
  for (final entry in directory.listSync(recursive: true)) {
    if (entry is File && entry.path.endsWith('.dart')) yield entry;
  }
}
