"""
Hindvi App - PC WebSocket Signaling Server (Python Fallback)
Standalone signaling relay for device requests, approvals, and WebRTC coordination.
"""

import sys
import json
import socket
import asyncio
from datetime import datetime

PORT = 8080

def get_local_ips():
    ips = []
    try:
        hostname = socket.gethostname()
        for ip in socket.gethostbyname_ex(hostname)[2]:
            if not ip.startswith("127."):
                ips.append(ip)
    except Exception:
        pass
    return ips

async def main():
    try:
        import websockets
    except ImportError:
        print("[INFO] 'websockets' package not found in Python. Installing or please use Dart server.")
        import subprocess
        subprocess.check_call([sys.executable, "-m", "pip", "install", "websockets"])
        import websockets

    port = PORT
    if len(sys.argv) > 1:
        try:
            port = int(sys.argv[1])
        except ValueError:
            pass

    clients = {}
    pending_requests = {}

    local_ips = get_local_ips()
    print("=" * 60)
    print("       HINDVI APP - PC WEBSOCKET SIGNALING SERVER (PYTHON)  ")
    print("=" * 60)
    print("[OK] Server Started successfully!")
    print(f"[OK] Port: {port}")
    print("[OK] Local IP Address(es):")
    if not local_ips:
        print("     - 127.0.0.1 (Localhost)")
    else:
        for ip in local_ips:
            print(f"     - {ip} (ws://{ip}:{port})")
    print("-" * 60)
    print("Waiting for connections...")
    print("(Keep this window open while using remote features)")
    print("Press Ctrl+C to stop the server.")
    print("=" * 60)

    async def handler(websocket):
        client_info = {"deviceId": None, "userId": None, "role": "CLIENT"}
        clients[websocket] = client_info
        print(f"[INFO] New client connected. Total clients: {len(clients)}")

        try:
            async for raw in websocket:
                try:
                    data = json.loads(raw)
                    msg_type = data.get("type")

                    if msg_type == "ping":
                        await websocket.send(json.dumps({"type": "pong", "timestamp": int(datetime.now().timestamp() * 1000)}))

                    elif msg_type == "register":
                        client_info["deviceId"] = data.get("deviceId")
                        client_info["userId"] = data.get("userId")
                        client_info["role"] = data.get("role", "CLIENT")
                        print(f"[REGISTER] Device={client_info['deviceId']}, Role={client_info['role']}")
                        await websocket.send(json.dumps({
                            "type": "registered",
                            "deviceId": client_info["deviceId"],
                            "role": client_info["role"],
                            "status": "OK"
                        }))
                        if client_info["role"] == "DEVELOPER":
                            req_list = list(pending_requests.values())
                            await websocket.send(json.dumps({"type": "pending_requests_list", "requests": req_list}))

                    elif msg_type == "device_request":
                        req_id = data.get("requestId", f"req_{int(datetime.now().timestamp() * 1000)}")
                        pending_requests[req_id] = data
                        await websocket.send(json.dumps({"type": "device_request_ack", "requestId": req_id, "status": "RECEIVED"}))
                        for ws, info in clients.items():
                            if info.get("role") == "DEVELOPER":
                                await ws.send(json.dumps({"type": "new_pending_request", "request": data}))

                    elif msg_type == "device_approval":
                        target = data.get("deviceId")
                        status = data.get("status", "APPROVED")
                        req_id = data.get("requestId")
                        if req_id in pending_requests:
                            del pending_requests[req_id]
                        for ws, info in clients.items():
                            if info.get("deviceId") == target:
                                await ws.send(json.dumps(data))

                    elif msg_type in ("permission_update", "device_revoke"):
                        target = data.get("deviceId")
                        for ws, info in clients.items():
                            if info.get("deviceId") == target:
                                await ws.send(json.dumps(data))

                    elif msg_type in ("webrtc_offer", "webrtc_answer", "webrtc_candidate", "sync_signal"):
                        target = data.get("to")
                        for ws, info in clients.items():
                            if info.get("deviceId") == target:
                                await ws.send(json.dumps(data))

                except Exception as ex:
                    print(f"[ERROR] Handling message: {ex}")
        except websockets.exceptions.ConnectionClosed:
            pass
        finally:
            if websocket in clients:
                del clients[websocket]
            print(f"[INFO] Client disconnected. Total remaining: {len(clients)}")

    async with websockets.serve(handler, "0.0.0.0", port):
        await asyncio.Future()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n[OK] Server stopped.")
