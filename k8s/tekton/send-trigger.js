#!/usr/bin/env node
// send-trigger-clean.js
// Usage: node send-trigger-clean.js --secret=mysecret --url=http://127.0.0.1:8080
const http = require('http');
const https = require('https');
const crypto = require('crypto');

function parseArgs() {
  const args = {};
  for (let i = 2; i < process.argv.length; i++) {
    const a = process.argv[i];
    if (a.startsWith('--')) {
      const [k, v] = a.split('=');
      args[k.replace(/^--/, '')] = v === undefined ? true : v;
    }
  }
  return args;
}

(async () => {
  const args = parseArgs();
  const secret = args.secret || process.env.GITHUB_SECRET || 'mysecret';
  const url = (args.url || process.env.EL_URL || 'http://127.0.0.1:8080').replace(/\/$/, '');

  const payload = {
    action: 'published',
    release: {
      id: 12345678,
      tag_name: 'v1.0.1',
      target_commitish: 'production',
      name: 'Release v1.0.1',
      body: 'Release notes here',
      draft: false,
      prerelease: false,
      created_at: new Date().toISOString(),
      published_at: new Date().toISOString()
    },
    repository: {
      id: 123456789,
      name: 'suma-ecommerce',
      full_name: 'AHMnesia/suma-ecommerce',
      private: false,
      owner: {
        login: 'AHMnesia',
        id: 123456,
        type: 'User'
      }
    },
    sender: {
      login: 'AHMnesia',
      id: 123456,
      type: 'User'
    },
    installation: {
      id: 12345678
    }
  };

  const body = JSON.stringify(payload);
  const signature = 'sha1=' + crypto.createHmac('sha1', secret).update(body).digest('hex');

  const target = new URL(url);
  const isHttps = target.protocol === 'https:';
  const options = {
    hostname: target.hostname,
    port: target.port || (isHttps ? 443 : 80),
    path: target.pathname || '/',
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(body),
      'X-GitHub-Event': 'release',
      'X-Hub-Signature': signature
    },
    timeout: 10000,
    rejectUnauthorized: false
  };

  const lib = isHttps ? https : http;
  console.log('Sending payload to', url);
  console.log('X-Hub-Signature:', signature);

  const req = lib.request(options, (res) => {
    console.log('Response status:', res.statusCode);
    let data = '';
    res.on('data', (chunk) => data += chunk);
    res.on('end', () => {
      if (data) console.log('Response body:', data);
      process.exit(res.statusCode >= 400 ? 1 : 0);
    });
  });
  req.on('error', (err) => {
    console.error('Request error:', err.message || err);
    process.exit(2);
  });
  req.write(body);
  req.end();
})();
