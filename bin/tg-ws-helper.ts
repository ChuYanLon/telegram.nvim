#!/usr/bin/env tsx
import { WebSocket } from 'ws';
const url = process.argv[2] || 'ws://localhost:8081';
const ws = new WebSocket(url);
ws.on('message', (data: Buffer) => process.stdout.write(data.toString() + '\n'));
ws.on('close', () => process.exit(0));
ws.on('error', (err: Error) => { console.error(err.message); process.exit(1); });
