const express = require('express');
const logger = require('./logger');
const metrics = require('./metrics');
const { version } = require('../package.json');

const APP_VERSION = process.env.APP_VERSION || version;

const app = express();
app.disable('x-powered-by');

// log and measure every request once the response is sent
app.use((req, res, next) => {
  const start = process.hrtime.bigint();

  res.on('finish', () => {
    const seconds = Number(process.hrtime.bigint() - start) / 1e9;
    // use the route pattern, not the raw url, so random paths don't create new label values
    const route = req.route ? req.route.path : 'unmatched';
    const labels = { method: req.method, route, status: res.statusCode };

    metrics.httpRequests.inc(labels);
    metrics.httpDuration.observe(labels, seconds);
    if (res.statusCode >= 500) metrics.httpErrors.inc(labels);

    // skip /metrics, prometheus hits it every few seconds
    if (route === '/metrics') return;

    const level = res.statusCode >= 500 ? 'error' : res.statusCode >= 400 ? 'warn' : 'info';
    logger[level]({
      method: req.method,
      path: route,
      status: res.statusCode,
      duration_ms: Math.round(seconds * 1000),
    }, 'request completed');
  });

  next();
});

app.get('/', (req, res) => {
  res.json({
    message: 'Hello from DevOps Task!',
    status: 'running',
    version: APP_VERSION,
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', metrics.register.contentType);
  res.send(await metrics.register.metrics());
});

app.use((req, res) => {
  res.status(404).json({ error: 'not found' });
});

// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  logger.error({ err }, 'unhandled error');
  res.status(500).json({ error: 'internal server error' });
});

module.exports = app;
