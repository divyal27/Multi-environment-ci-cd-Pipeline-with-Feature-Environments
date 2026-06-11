import { test, expect } from '@playwright/test';

test.describe('Ephemeral Environment Smoke Tests', () => {
  test('Health endpoint returns 200', async ({ request }) => {
    const resp = await request.get('/health');
    expect(resp.status()).toBe(200);
  });

  test('Homepage loads successfully', async ({ page }) => {
    const resp = await page.goto('/');
    expect(resp?.status()).toBe(200);
    // Verify page has content and is not blank
    const title = await page.title();
    expect(title).toBeTruthy();
  });

  test('API version endpoint returns valid JSON', async ({ request }) => {
    const resp = await request.get('/api/version');
    expect(resp.status()).toBe(200);
    const body = await resp.json();
    expect(body).toHaveProperty('version');
    expect(typeof body.version).toBe('string');
  });

  test('Database connection is operational', async ({ request }) => {
    const resp = await request.get('/health/db');
    expect(resp.status()).toBe(200);
    const body = await resp.json();
    expect(body).toHaveProperty('database');
    expect(body.database).toBe('connected');
  });

  test('Static assets are served correctly', async ({ page }) => {
    // Try to load favicon or a known static asset
    const resp = await page.goto('/favicon.ico');
    expect(resp?.status()).toBe(200);
  });

  test('CORS headers are present on API responses', async ({ request }) => {
    const resp = await request.get('/api/version');
    const origin = resp.headers()['access-control-allow-origin'];
    expect(origin).toBe('*');
  });

  test('Page renders without console errors', async ({ page }) => {
    const consoleErrors: string[] = [];
    page.on('console', (msg) => {
      if (msg.type() === 'error') {
        consoleErrors.push(msg.text());
      }
    });
    await page.goto('/');
    expect(consoleErrors.length).toBe(0);
  });
});
