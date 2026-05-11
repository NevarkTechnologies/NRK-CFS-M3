/// Stub for non-web platforms. Never actually called because
/// [kIsWeb] is false on those platforms.
void downloadCsvOnWeb(String fileName, String csvData) {
  throw UnsupportedError('downloadCsvOnWeb is only available on web.');
}