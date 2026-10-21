/// Minimum severity to deliver, from most to least detailed.
enum InappifyLogLevel { verbose, debug, info, warn, error }

/// Receives SDK messages after filtering. Replaces the default console output.
typedef InappifyLogHandler =
    void Function(InappifyLogLevel level, String message);
