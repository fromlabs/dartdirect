part of directbackendapi;

class Loggable {
  @Inject
  Provider<Logger> _LOGGER_PROVIDER;

  Logger get LOGGER => _LOGGER_PROVIDER.get();

  bool isLoggable(Level value) => LOGGER.isLoggable(value);

  void shout(String message, [Object error, StackTrace stackTrace]) => LOGGER.shout(message, error, stackTrace);

  void severe(String message, [Object error, StackTrace stackTrace]) => LOGGER.severe(message, error, stackTrace);

  void warning(String message, [Object error, StackTrace stackTrace]) => LOGGER.warning(message, error, stackTrace);

  void info(String message, [Object error, StackTrace stackTrace]) => LOGGER.info(message, error, stackTrace);

  void config(String message, [Object error, StackTrace stackTrace]) => LOGGER.config(message, error, stackTrace);

  void fine(String message, [Object error, StackTrace stackTrace]) => LOGGER.fine(message, error, stackTrace);

  void finer(String message, [Object error, StackTrace stackTrace]) => LOGGER.finer(message, error, stackTrace);

  void finest(String message, [Object error, StackTrace stackTrace]) => LOGGER.finest(message, error, stackTrace);
}
