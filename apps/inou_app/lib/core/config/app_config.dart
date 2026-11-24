/// Tunable application defaults aligned with `docs/02-开发文档.md` §16.3.
abstract final class AppConfig {
  static const int masteryStreak = 3;
  static const bool partialClearsStreak = false;
  static const int captureMaxParallel = 3;
  static const int captureMaxPagesPerBatch = 6;
  static const int aiRpmLimit = 30;
  static const int aiCacheTtlDays = 7;
  static const int reportMinWrong = 5;
  static const int weakHalfLifeDays = 30;
  static const int weakWindowDays = 90;
  static const int dupSimhashThreshold = 3;
  static const double judgeLowConfidence = 0.5;
  static const String defaultPaperSize = 'A4';
}
