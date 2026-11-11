const pino = require('pino');

const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  base: { env: process.env.APP_ENV || 'development' },
  timestamp: pino.stdTimeFunctions.isoTime,
  formatters: {
    // "level":"info" instead of "level":30, easier to filter in Loki
    level: (label) => ({ level: label }),
  },
});

module.exports = logger;
