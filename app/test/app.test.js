const request = require('supertest');
const app = require('../src/app');

describe('GET /', () => {
  it('returns message, status and version', async () => {
    const res = await request(app).get('/');

    expect(res.status).toBe(200);
    expect(res.body.message).toBe('Hello from DevOps Task!');
    expect(res.body.status).toBe('running');
    expect(res.body.version).toBeDefined();
  });
});

describe('GET /health', () => {
  it('returns ok', async () => {
    const res = await request(app).get('/health');

    expect(res.status).toBe(200);
    expect(res.body).toEqual({ status: 'ok' });
  });
});

describe('GET /metrics', () => {
  it('exposes prometheus metrics', async () => {
    await request(app).get('/');
    const res = await request(app).get('/metrics');

    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toContain('text/plain');
    expect(res.text).toContain('http_requests_total');
    expect(res.text).toContain('http_errors_total');
    expect(res.text).toContain('http_request_duration_seconds_bucket');
  });
});

describe('unknown route', () => {
  it('returns 404', async () => {
    const res = await request(app).get('/does-not-exist');

    expect(res.status).toBe(404);
  });
});
