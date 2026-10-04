import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';

test('Las migraciones tienen versiones únicas y contenido sin secretos', () => {
  const files = readdirSync('migrations').filter(file => file.endsWith('.sql'));
  assert.ok(files.length > 0);
  const versions = new Set();
  for (const file of files) {
    assert.match(file, /^\d{14}_[a-z0-9-]+\.sql$/);
    assert.ok(!versions.has(file.slice(0, 14)), 'Versión duplicada');
    versions.add(file.slice(0, 14));
    const sql = readFileSync(`migrations/${file}`, 'utf8');
    assert.ok(sql.trim().length > 0);
    assert.doesNotMatch(sql, /uak_[\w-]{16,}|eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\./);
    assert.doesNotMatch(sql, /^\s*(COMMIT|ROLLBACK);/im);
  }
});

test('Los entornos de ejemplo no contienen claves', () => {
  const env = readFileSync('.env.example', 'utf8');
  assert.match(env, /^INSFORGE_API_KEY=$/m);
  assert.match(env, /^INSFORGE_ANON_KEY=$/m);
});
