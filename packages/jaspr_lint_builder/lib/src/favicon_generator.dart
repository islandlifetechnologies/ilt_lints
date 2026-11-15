import 'dart:typed_data';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Pure-Dart favicon generator that validates an input PNG image and resizes it
/// into standard web favicon sizes (`.ico` and `.png`).
class const FaviconGenerator({final FileSystem fs = const LocalFileSystem()}) {
  static const _pngSizes = <String, int>{
    'apple-touch-icon.png': 180,
    'favicon-16x16.png': 16,
    'favicon-32x32.png': 32,
    'favicon-48x48.png': 48,
    'favicon-192x192.png': 192,
    'favicon-512x512.png': 512,
  };

  /// Reads [faviconFilePath] (which must be a valid `.png` file), resizes it
  /// into standard favicon assets in [outputDirectoryPath], and returns the
  /// paths of the generated files.
  List<String> generateFavicons({
    required String faviconFilePath,
    required String outputDirectoryPath,
  }) {
    if (!faviconFilePath.toLowerCase().endsWith('.png')) {
      throw FormatException(
        'Favicon file must be a PNG file (.png): $faviconFilePath',
      );
    }

    final sourceFile = fs.file(faviconFilePath);
    if (!sourceFile.existsSync()) {
      throw FormatException('Favicon file does not exist: $faviconFilePath');
    }

    final rawBytes = Uint8List.fromList(sourceFile.readAsBytesSync());
    final pngDecoder = img.PngDecoder();
    if (!pngDecoder.isValidFile(rawBytes)) {
      throw FormatException(
        'Favicon file is not a valid PNG image: $faviconFilePath',
      );
    }

    final decodedImage = pngDecoder.decode(rawBytes);
    if (decodedImage == null) {
      throw FormatException(
        'Failed to decode PNG favicon image: $faviconFilePath',
      );
    }

    final outputDir = fs.directory(outputDirectoryPath);
    if (!outputDir.existsSync()) {
      outputDir.createSync(recursive: true);
    }

    final resizedBySize = <int, img.Image>{};
    img.Image resizeTo(int size) => resizedBySize.putIfAbsent(
      size,
      () => img.copyResize(
        decodedImage,
        height: size,
        interpolation: img.Interpolation.average,
        width: size,
      ),
    );

    final generatedFiles = <String>[];

    void writeBytesFile(String fileName, Uint8List bytes) {
      final fullPath = p.join(outputDir.path, fileName);
      final outFile = fs.file(fullPath);
      if (!outFile.parent.existsSync()) {
        outFile.parent.createSync(recursive: true);
      }
      outFile.writeAsBytesSync(bytes);
      generatedFiles.add(fullPath);
    }

    for (final entry in _pngSizes.entries) {
      final resized = resizeTo(entry.value);
      final encodedPng = img.encodePng(resized);
      writeBytesFile(entry.key, encodedPng);
    }

    final icoBytes = img.IcoEncoder().encodeImages([
      resizeTo(16),
      resizeTo(32),
      resizeTo(48),
    ]);
    writeBytesFile('favicon.ico', icoBytes);

    return List<String>.unmodifiable(generatedFiles);
  }
}
