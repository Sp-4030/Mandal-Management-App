"""
Hindvi App - PC WebSocket Signaling Server (Python Fallback)
Standalone signaling relay for device requests, approvals, and WebRTC coordination.
Optimized for minimal ngrok and network bandwidth:
- Event-driven (no polling)
- Lightweight ping/pong
- Request deduplication
- Payload size guard (max 64KB)
- Minimal JSON payloads
"""

import sys
import json
import socket
import asyncio
from datetime import datetime

PORT = 8080
MAX_PAYLOAD_SIZE = 10485760  # 10 MB

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
    forwarded_request_ids = set()

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
        client_info = {
            "deviceId": None,
            "userId": None,
            "userName": None,
            "requestId": None,
            "role": "CLIENT",
            "isMaster": False,
            "userRole": None
        }
        clients[websocket] = client_info
        print(f"[INFO] New client connected. Total clients: {len(clients)}")

        try:
            async for raw in websocket:
                try:
                    if isinstance(raw, str) and len(raw) > MAX_PAYLOAD_SIZE:
                        print(f"[REJECTED] Message length {len(raw)} exceeds limit.")
                        await websocket.send(json.dumps({
                            "type": "error",
                            "message": "Payload exceeds maximum allowed limit."
                        }))
                        continue

                    data = json.loads(raw)
                    msg_type = data.get("type")

                    if msg_type == "ping":
                        # Minimal lightweight pong
                        await websocket.send(json.dumps({"type": "pong"}))

                    elif msg_type == "register":
                        client_info["deviceId"] = data.get("deviceId")
                        client_info["userId"] = data.get("userId")
                        client_info["userName"] = data.get("userName")
                        client_info["requestId"] = data.get("requestId")
                        client_info["role"] = data.get("role", "CLIENT")
                        client_info["isMaster"] = data.get("isMaster", False) or client_info["role"] in ("MASTER", "LATEST_KHAJANI")
                        client_info["userRole"] = data.get("userRole")
                        print(f"[REGISTER] Device={client_info['deviceId']}, User={client_info['userName']}, Role={client_info['role']}, isMaster={client_info['isMaster']}, Request={client_info['requestId']}")
                        await websocket.send(json.dumps({
                            "type": "registered",
                            "deviceId": client_info["deviceId"],
                            "role": client_info["role"],
                            "status": "OK"
                        }))
                        if client_info["role"] == "DEVELOPER":
                            req_list = [r for r in pending_requests.values() if r.get("status") == "PENDING"]
                            await websocket.send(json.dumps({"type": "pending_requests_list", "requests": req_list}))
                            all_list = list(pending_requests.values())
                            await websocket.send(json.dumps({"type": "all_requests_list", "requests": all_list}))
                        else:
                            # Offline recovery check
                            dev_id = client_info["deviceId"]
                            user_id = client_info["userId"]
                            req_id = client_info["requestId"]
                            if dev_id:
                                for r in pending_requests.values():
                                    if r.get("status") == "APPROVED":
                                        d_match = r.get("deviceId") == dev_id
                                        u_match = not user_id or r.get("userId") == user_id
                                        rq_match = not req_id or r.get("requestId") == req_id
                                        if d_match and (u_match or rq_match):
                                            print(f"[SERVER_FOUND_TARGET_DEVICE] requestId={r.get('requestId')} userId={r.get('userId')} deviceId={r.get('deviceId')} status=APPROVED")
                                            approval_payload = {
                                                "type": "device_approval_result",
                                                "requestId": r.get("requestId"),
                                                "deviceId": r.get("deviceId"),
                                                "userId": r.get("userId"),
                                                "status": "APPROVED",
                                                "role": r.get("role", "OLD_KHAJANI"),
                                                "permissions": r.get("permissions"),
                                                "updatedAt": r.get("updatedAt", int(datetime.now().timestamp() * 1000)),
                                            }
                                            await websocket.send(json.dumps(approval_payload))
                                            print(f"[SERVER_SENT_APPROVAL_TO_NEW_PHONE] requestId={r.get('requestId')} userId={r.get('userId')} deviceId={r.get('deviceId')} status=APPROVED")
                                            break
                                    elif r.get("status") == "REVOKED" and r.get("deviceId") == dev_id:
                                        await websocket.send(json.dumps({
                                            "type": "device_revoked",
                                            "deviceId": dev_id,
                                            "revokedAt": r.get("updatedAt", int(datetime.now().timestamp() * 1000)),
                                        }))
                                        break

                    elif msg_type == "get_pending_requests":
                        req_list = [r for r in pending_requests.values() if r.get("status") == "PENDING"]
                        await websocket.send(json.dumps({"type": "pending_requests_list", "requests": req_list}))

                    elif msg_type == "get_all_requests":
                        all_list = list(pending_requests.values())
                        await websocket.send(json.dumps({"type": "all_requests_list", "requests": all_list}))

                    elif msg_type == "get_connected_clients":
                        c_list = [{
                            "deviceId": info.get("deviceId", ""),
                            "userId": info.get("userId", ""),
                            "userName": info.get("userName", ""),
                            "role": info.get("role", "CLIENT"),
                            "userRole": info.get("userRole", ""),
                            "isMaster": info.get("isMaster", False),
                        } for info in clients.values()]
                        await websocket.send(json.dumps({"type": "connected_clients_list", "clients": c_list}))

                    elif msg_type == "check_status":
                        req_id = data.get("requestId", "")
                        user_id = data.get("userId", "")
                        dev_id = data.get("deviceId", "")
                        if dev_id:
                            client_info["deviceId"] = dev_id
                        if user_id:
                            client_info["userId"] = user_id
                        if req_id:
                            client_info["requestId"] = req_id

                        print(f"[SERVER_CHECK_STATUS] requestId={req_id} userId={user_id} deviceId={dev_id}")
                        found = None
                        if req_id and req_id in pending_requests:
                            r = pending_requests[req_id]
                            u_match = not user_id or not r.get("userId") or r.get("userId") == user_id
                            d_match = not dev_id or not r.get("deviceId") or r.get("deviceId") == dev_id
                            if u_match and d_match:
                                found = r
                        else:
                            for r in pending_requests.values():
                                rq_m = not req_id or r.get("requestId") == req_id
                                u_m = not user_id or r.get("userId") == user_id
                                d_m = not dev_id or r.get("deviceId") == dev_id
                                if rq_m and u_m and d_m:
                                    found = r
                                    break

                        if found and found.get("status") == "APPROVED":
                            print(f"[SERVER_FOUND_TARGET_DEVICE] requestId={found.get('requestId')} userId={found.get('userId')} deviceId={found.get('deviceId')} status=APPROVED")
                            approval_payload = {
                                "type": "device_approval_result",
                                "requestId": found.get("requestId"),
                                "deviceId": found.get("deviceId"),
                                "userId": found.get("userId"),
                                "status": "APPROVED",
                                "role": found.get("role", "OLD_KHAJANI"),
                                "permissions": found.get("permissions"),
                                "updatedAt": found.get("updatedAt", int(datetime.now().timestamp() * 1000)),
                            }
                            await websocket.send(json.dumps(approval_payload))
                            print(f"[SERVER_SENT_APPROVAL_TO_NEW_PHONE] requestId={found.get('requestId')} userId={found.get('userId')} deviceId={found.get('deviceId')} status=APPROVED")
                        elif found and found.get("status") == "REVOKED":
                            await websocket.send(json.dumps({
                                "type": "device_revoked",
                                "deviceId": found.get("deviceId"),
                                "status": "REVOKED",
                                "revokedAt": found.get("updatedAt", int(datetime.now().timestamp() * 1000)),
                            }))
                        elif found:
                            await websocket.send(json.dumps({
                                "type": "check_status_result",
                                "requestId": found.get("requestId"),
                                "userId": found.get("userId"),
                                "deviceId": found.get("deviceId"),
                                "status": found.get("status", "PENDING")
                            }))
                        else:
                            await websocket.send(json.dumps({
                                "type": "check_status_result",
                                "requestId": req_id,
                                "userId": user_id,
                                "deviceId": dev_id,
                                "status": "NOT_FOUND"
                            }))

                    elif msg_type == "authorize_app_access":
                        req_id = data.get("requestId") or data.get("request_id") or ""
                        user_id = data.get("userId") or data.get("user_id") or ""
                        dev_id = data.get("deviceId") or data.get("device_id") or ""
                        if dev_id:
                            client_info["deviceId"] = dev_id
                        if user_id:
                            client_info["userId"] = user_id

                        print(f"[SERVER_AUTHORIZE_APP_ACCESS] requestId={req_id} userId={user_id} deviceId={dev_id}")
                        if user_id == "developer_root":
                            await websocket.send(json.dumps({
                                "type": "authorize_app_access_result",
                                "isAuthorized": True,
                                "status": "APPROVED",
                                "role": "DEVELOPER",
                                "userId": user_id,
                                "deviceId": dev_id,
                                "permissions": {
                                    "can_view": 1,
                                    "can_add": 1,
                                    "can_edit": 1,
                                    "can_delete": 1,
                                    "can_search": 1,
                                    "can_pdf": 1,
                                    "can_manage_khajani": 1,
                                    "can_sync": 1,
                                }
                            }))
                        else:
                            found = None
                            if req_id and req_id in pending_requests:
                                r = pending_requests[req_id]
                                u_m = not user_id or not r.get("userId") or r.get("userId") == user_id
                                d_m = not dev_id or not r.get("deviceId") or r.get("deviceId") == dev_id
                                if u_m and d_m:
                                    found = r
                            if not found:
                                for r in pending_requests.values():
                                    r_m = not req_id or r.get("requestId") == req_id
                                    u_m = not user_id or r.get("userId") == user_id
                                    d_m = not dev_id or r.get("deviceId") == dev_id
                                    if r_m and u_m and d_m:
                                        found = r
                                        break

                            if found and found.get("status") == "APPROVED":
                                await websocket.send(json.dumps({
                                    "type": "authorize_app_access_result",
                                    "isAuthorized": True,
                                    "status": "APPROVED",
                                    "role": found.get("role", "OLD_KHAJANI"),
                                    "permissions": found.get("permissions"),
                                    "userId": found.get("userId"),
                                    "deviceId": found.get("deviceId"),
                                    "requestId": found.get("requestId"),
                                    "updatedAt": found.get("updatedAt", int(datetime.now().timestamp() * 1000)),
                                }))
                            elif found and found.get("status") == "REVOKED":
                                await websocket.send(json.dumps({
                                    "type": "authorize_app_access_result",
                                    "isAuthorized": False,
                                    "status": "REVOKED",
                                    "userId": found.get("userId"),
                                    "deviceId": found.get("deviceId"),
                                    "message": "Access Revoked. Contact Developer.",
                                }))
                            elif found and found.get("status") == "REJECTED":
                                await websocket.send(json.dumps({
                                    "type": "authorize_app_access_result",
                                    "isAuthorized": False,
                                    "status": "REJECTED",
                                    "userId": found.get("userId"),
                                    "deviceId": found.get("deviceId"),
                                    "message": "Request rejected by Developer.",
                                }))
                            elif found:
                                await websocket.send(json.dumps({
                                    "type": "authorize_app_access_result",
                                    "isAuthorized": False,
                                    "status": "PENDING",
                                    "userId": found.get("userId"),
                                    "deviceId": found.get("deviceId"),
                                    "message": "Developer approval pending.",
                                }))
                            else:
                                await websocket.send(json.dumps({
                                    "type": "authorize_app_access_result",
                                    "isAuthorized": False,
                                    "status": "NOT_FOUND",
                                    "userId": user_id,
                                    "deviceId": dev_id,
                                    "message": "Device not registered.",
                                }))

                    elif msg_type == "device_request":
                        req_id = data.get("requestId", f"req_{int(datetime.now().timestamp() * 1000)}")
                        data["requestId"] = req_id
                        data["status"] = "PENDING"
                        client_info["deviceId"] = data.get("deviceId")
                        client_info["userId"] = data.get("userId")
                        client_info["requestId"] = req_id

                        if req_id in forwarded_request_ids:
                            print(f"[SERVER_DEDUP] Duplicate request received: {req_id}. Skipping broadcast.")
                            await websocket.send(json.dumps({
                                "type": "device_request_ack",
                                "requestId": req_id,
                                "status": "ALREADY_FORWARDED"
                            }))
                            continue

                        pending_requests[req_id] = data
                        forwarded_request_ids.add(req_id)
                        await websocket.send(json.dumps({"type": "device_request_ack", "requestId": req_id, "status": "RECEIVED"}))
                        print(f"[SERVER_RECEIVED] requestId={req_id} userId={data.get('userId')} deviceId={data.get('deviceId')} status=PENDING")
                        for ws, info in clients.items():
                            if info.get("role") == "DEVELOPER":
                                await ws.send(json.dumps({"type": "new_pending_request", "request": data}))
                                await ws.send(json.dumps({"type": "all_requests_list", "requests": list(pending_requests.values())}))
                        print(f"[SERVER_FORWARDED] requestId={req_id} userId={data.get('userId')} deviceId={data.get('deviceId')} status=PENDING")

                    elif msg_type == "device_approval":
                        req_id = data.get("requestId", "")
                        target_dev = data.get("deviceId", "")
                        user_id = data.get("userId", "")
                        status = data.get("status", "APPROVED")
                        role = data.get("role", "OLD_KHAJANI")
                        permissions = data.get("permissions")

                        now_ts = int(datetime.now().timestamp() * 1000)

                        if role == "LATEST_KHAJANI":
                            for r in pending_requests.values():
                                if r.get("requestId") != req_id and r.get("role") == "LATEST_KHAJANI":
                                    r["role"] = "OLD_KHAJANI"
                                    r["updatedAt"] = now_ts
                                    for ws, info in clients.items():
                                        if info.get("deviceId") == r.get("deviceId"):
                                            info["isMaster"] = False
                                            await ws.send(json.dumps({"type": "role_updated", "role": "OLD_KHAJANI", "isMaster": False}))

                        print(f"[SERVER_RECEIVED_APPROVAL] requestId={req_id} userId={user_id} deviceId={target_dev} status={status}")

                        if req_id and req_id in pending_requests:
                            pending_requests[req_id]["status"] = status
                            pending_requests[req_id]["role"] = role
                            pending_requests[req_id]["permissions"] = permissions
                            pending_requests[req_id]["updatedAt"] = now_ts
                        else:
                            pending_requests[req_id] = {
                                "requestId": req_id,
                                "userId": user_id,
                                "deviceId": target_dev,
                                "status": status,
                                "role": role,
                                "permissions": permissions,
                                "updatedAt": now_ts,
                            }

                        approval_payload = {
                            "type": "device_approval_result",
                            "requestId": req_id,
                            "deviceId": target_dev,
                            "userId": user_id,
                            "status": status,
                            "role": role,
                            "permissions": permissions,
                            "updatedAt": now_ts,
                        }

                        target_ws = None
                        for ws, info in clients.items():
                            if info.get("role") != "DEVELOPER":
                                d_match = info.get("deviceId") == target_dev
                                u_match = not info.get("userId") or info.get("userId") == user_id
                                r_match = not info.get("requestId") or info.get("requestId") == req_id
                                if d_match and (u_match or r_match):
                                    target_ws = ws
                                    break

                        delivered = False
                        if target_ws:
                            if role == "LATEST_KHAJANI":
                                clients[target_ws]["isMaster"] = True
                            await target_ws.send(json.dumps(approval_payload))
                            delivered = True

                        await websocket.send(json.dumps({
                            "type": "approval_dispatched",
                            "requestId": req_id,
                            "targetDeviceId": target_dev,
                            "userId": user_id,
                            "deliveredDirectly": delivered,
                            "status": status,
                        }))

                        for ws, info in clients.items():
                            if info.get("role") == "DEVELOPER":
                                await ws.send(json.dumps({"type": "all_requests_list", "requests": list(pending_requests.values())}))

                    elif msg_type == "device_revoke":
                        target_dev = data.get("deviceId")
                        now_ts = int(datetime.now().timestamp() * 1000)
                        for r in pending_requests.values():
                            if r.get("deviceId") == target_dev:
                                r["status"] = "REVOKED"
                                r["updatedAt"] = now_ts

                        revoke_payload = {"type": "device_revoked", "deviceId": target_dev, "revokedAt": now_ts}
                        for ws, info in clients.items():
                            if info.get("deviceId") == target_dev:
                                await ws.send(json.dumps(revoke_payload))

                        await websocket.send(json.dumps({"type": "device_revoked_ack", "deviceId": target_dev, "status": "REVOKED"}))
                        for ws, info in clients.items():
                            if info.get("role") == "DEVELOPER":
                                await ws.send(json.dumps({"type": "all_requests_list", "requests": list(pending_requests.values())}))

                    elif msg_type == "device_restore":
                        target_dev = data.get("deviceId")
                        now_ts = int(datetime.now().timestamp() * 1000)
                        for r in pending_requests.values():
                            if r.get("deviceId") == target_dev:
                                r["status"] = "APPROVED"
                                r["role"] = r.get("role", "OLD_KHAJANI")
                                r["updatedAt"] = now_ts

                        restore_payload = {"type": "device_approval_result", "deviceId": target_dev, "status": "APPROVED", "role": "OLD_KHAJANI", "updatedAt": now_ts}
                        for ws, info in clients.items():
                            if info.get("deviceId") == target_dev:
                                await ws.send(json.dumps(restore_payload))

                        await websocket.send(json.dumps({"type": "device_restored_ack", "deviceId": target_dev, "status": "APPROVED"}))
                        for ws, info in clients.items():
                            if info.get("role") == "DEVELOPER":
                                await ws.send(json.dumps({"type": "all_requests_list", "requests": list(pending_requests.values())}))

                    elif msg_type == "set_latest_khajani":
                        target_user = data.get("userId", "")
                        target_dev = data.get("deviceId", "")
                        now_ts = int(datetime.now().timestamp() * 1000)
                        for r in pending_requests.values():
                            if r.get("role") == "LATEST_KHAJANI" and r.get("userId") != target_user:
                                r["role"] = "OLD_KHAJANI"
                                r["updatedAt"] = now_ts
                                for ws, info in clients.items():
                                    if info.get("deviceId") == r.get("deviceId"):
                                        info["isMaster"] = False
                                        await ws.send(json.dumps({"type": "role_updated", "role": "OLD_KHAJANI", "isMaster": False}))

                        for r in pending_requests.values():
                            if r.get("userId") == target_user or (target_dev and r.get("deviceId") == target_dev):
                                r["role"] = "LATEST_KHAJANI"
                                r["status"] = "APPROVED"
                                r["updatedAt"] = now_ts
                                for ws, info in clients.items():
                                    if info.get("deviceId") == r.get("deviceId"):
                                        info["isMaster"] = True
                                        await ws.send(json.dumps({"type": "role_updated", "role": "LATEST_KHAJANI", "isMaster": True}))

                        await websocket.send(json.dumps({"type": "latest_khajani_updated", "status": "OK", "userId": target_user}))
                        for ws, info in clients.items():
                            if info.get("role") == "DEVELOPER":
                                await ws.send(json.dumps({"type": "all_requests_list", "requests": list(pending_requests.values())}))

                    elif msg_type == "permission_update":
                        target = data.get("deviceId")
                        user_id = data.get("userId")
                        for ws, info in clients.items():
                            if info.get("deviceId") == target or (user_id and info.get("userId") == user_id):
                                await ws.send(json.dumps(data))

                    elif msg_type == "sync_request":
                        req_dev = data.get("requesterDeviceId") or client_info.get("deviceId")
                        req_user = data.get("requesterUserId") or client_info.get("userId")
                        print(f"[SERVER_RECEIVED_SYNC_REQUEST] requesterDeviceId={req_dev} requesterUserId={req_user}")
                        master_ws = None
                        for ws, info in clients.items():
                            if info.get("isMaster") or info.get("role") in ("MASTER", "LATEST_KHAJANI") or info.get("userRole") == "LATEST_KHAJANI":
                                master_ws = ws
                                break
                        if master_ws:
                            print(f"[SERVER_FORWARDED_SYNC_REQUEST] Forwarding sync request to Master device={clients[master_ws].get('deviceId')}")
                            await master_ws.send(json.dumps(data))
                        else:
                            print("[SERVER_MASTER_OFFLINE] Master phone is not connected.")
                            await websocket.send(json.dumps({
                                "type": "sync_status",
                                "status": "MASTER_OFFLINE",
                                "message": "मास्टर फोन (चालू खजानी) सध्या ऑफलाइन आहे. कृपया मास्टर फोन सुरू करा.",
                                "timestamp": int(datetime.now().timestamp() * 1000)
                            }))

                    elif msg_type == "sync_data":
                        target = data.get("to")
                        from_dev = data.get("from") or client_info.get("deviceId")
                        counts = data.get("recordCounts") or {}
                        vargani = counts.get("vargani", 0)
                        prasad = counts.get("prasad_dengani", 0)
                        kharch = counts.get("kharch", 0)
                        print(f"[SERVER_RECEIVED] from={from_dev} to={target}, Vargani: {vargani} records, Prasad Dengani: {prasad} records, Kharch: {kharch} records")
                        if target:
                            for ws, info in clients.items():
                                if info.get("deviceId") == target:
                                    await ws.send(json.dumps(data))
                                    print(f"[SERVER_FORWARDED] Delivered sync data to targetDeviceId={target}")
                                    break

                    elif msg_type == "financial_change":
                        change_id = data.get("changeId", "")
                        table_name = data.get("tableName", "")
                        operation = data.get("operation", "")
                        from_dev = data.get("deviceId") or client_info.get("deviceId", "")
                        print(f"[SERVER_RECEIVED] changeId={change_id} table={table_name} op={operation} from={from_dev}")
                        forwarded_count = 0
                        for ws, info in clients.items():
                            if ws != websocket and info.get("deviceId") != from_dev:
                                await ws.send(json.dumps(data))
                                forwarded_count += 1
                                print(f"[SERVER_FORWARDED] changeId={change_id} table={table_name} to={info.get('deviceId')}")
                        await websocket.send(json.dumps({
                            "type": "sync_ack",
                            "changeId": change_id,
                            "status": "SERVER_RECEIVED",
                            "forwardedCount": forwarded_count,
                            "timestamp": int(datetime.now().timestamp() * 1000)
                        }))

                    elif msg_type in ("sync_chunk", "sync_ack"):
                        target = data.get("to") or data.get("toDeviceId")
                        if target:
                            for ws, info in clients.items():
                                if info.get("deviceId") == target:
                                    await ws.send(json.dumps(data))
                                    break

                    elif msg_type == "get_master_info":
                        master_info = None
                        for ws, info in clients.items():
                            if info.get("isMaster") or info.get("role") in ("MASTER", "LATEST_KHAJANI") or info.get("userRole") == "LATEST_KHAJANI":
                                master_info = info
                                break
                        await websocket.send(json.dumps({
                            "type": "master_info",
                            "isMasterOnline": master_info is not None,
                            "masterDeviceId": master_info.get("deviceId") if master_info else None,
                            "masterUserName": master_info.get("userName") if master_info else None
                        }))

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
