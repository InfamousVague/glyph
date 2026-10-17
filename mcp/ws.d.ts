/**
 * The `ws` package as the connector uses it: a WebSocket constructor with the browser's `on…` handlers, which is all
 * the relay's transport (tauri/src/app/core/live/transport.ts) asks of one (mcp/live.ts), and a server for a test to
 * stand in for the relay over a real socket (mcp/live.test.ts). The package ships no types, and nothing needs more.
 */
declare module 'ws' {
  const WebSocket: new (url: string) => {
    send(data: string): void;
    close(code?: number): void;
    onopen: ((event: unknown) => void) | null;
    onmessage: ((event: { data: unknown }) => void) | null;
    onclose: ((event: { code: number }) => void) | null;
    onerror: ((event: unknown) => void) | null;
  };
  export default WebSocket;

  export interface ServerSocket {
    send(data: string): void;
    close(code?: number): void;
    on(event: 'message', listener: (data: { toString(): string }) => void): void;
    on(event: 'close', listener: () => void): void;
  }

  export class WebSocketServer {
    constructor(options: { port: number; host?: string });
    address(): { port: number };
    on(event: 'listening', listener: () => void): void;
    on(event: 'connection', listener: (socket: ServerSocket) => void): void;
    close(done?: () => void): void;
  }
}
