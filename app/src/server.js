const app = require('./app');
const logger = require('./logger');

const PORT = Number(process.env.PORT) || 8080;

const server = app.listen(PORT, () => {
  logger.info({ port: PORT }, 'server started');
});

function shutdown(signal) {
  logger.info({ signal }, 'shutting down');

  // stop taking new connections, let in-flight requests finish
  server.close(() => {
    logger.info('server closed');
    process.exit(0);
  });

  // don't hang forever on keep-alive connections
  setTimeout(() => {
    logger.warn('forcing exit after timeout');
    process.exit(1);
  }, 10000).unref();
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
