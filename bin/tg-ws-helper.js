const { WebSocket } = require('ws');
const url = process.argv[2] || 'ws://localhost:8081';
const ws = new WebSocket(url);
ws.on('message', (data) => process.stdout.write(data.toString() + '\n'));
ws.on('close', () => process.exit(0));
ws.on('error', (err) => { console.error(err.message); process.exit(1); });
