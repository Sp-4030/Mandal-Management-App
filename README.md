# Hindvi Swarajya Mandal Management (हिंदवी स्वराज्य मंडळ व्यवस्थापन)

A secure, offline-first Flutter application for managing Ganeshotsav / Mandal collections, contributions, market expenses, and generating Devanagari annual financial reports.

---

## 📌 Overview

Hindvi-App delivers a distributed architecture where:
- **Latest Khajani Phone = MASTER SQLite Financial Database** (`hindvi_latest.db`).
- **PC = Signaling & Communication Relay Server** (WebSocket / ngrok). **NO financial data is stored on the PC disk.**
- **Target Phones (Developer, Old Khajani, New Khajani)** = Granted granular role-based permissions (`canView`, `canSearch`, `canPdf`, `canAdd`, `canEdit`, `canDelete`, `canSync`).
- **100% Offline First** = Once synced, all tables, search functionality, and Annual Report PDF generation operate strictly offline without internet or server access.

---

## 🏗️ Low-Level Design (LLD) Diagrams

### 1. High-Level Architecture & End-to-End Data Flow

```mermaid
flowchart TD
    subgraph MasterDevice["Master Phone (Latest Khajani)"]
        M_DB[("Local SQLite Master<br/>hindvi_latest.db")]
        M_Sync[RemoteSyncService<br/>Master Listener]
        M_Auth[AuthService<br/>Role: LATEST_KHAJANI]
    end

    subgraph ServerRelay["PC WebSocket Relay Server"]
        WS_Server["Signaling Server (Port 8080 / ngrok)<br/>In-Memory Session Router"]
        WS_Zero["Zero Disk Storage<br/>(No financial data saved on PC)"]
    end

    subgraph DeveloperDevice["Developer Device"]
        Dev_UI["Approval & Role Control"]
        Dev_Auth["AuthService<br/>Role: DEVELOPER"]
    end

    subgraph TargetDevice["Target Phone (Old/New Khajani)"]
        T_UI["Forms / Tables / PDF Viewer"]
        T_Auth["AuthService<br/>Permissions Check"]
        T_Sync["RemoteSyncService<br/>Target Requester"]
        T_DB[("Local SQLite Target<br/>hindvi_latest.db")]
    end

    %% Device Approval Flow
    T_UI -- "1. Request Device Approval" --> WS_Server
    WS_Server -- "2. Forward Pending Request" --> Dev_UI
    Dev_UI -- "3. Approve + Assign Permissions" --> WS_Server
    WS_Server -- "4. Deliver Approval Result" --> T_UI

    %% Financial Data Sync Flow
    T_UI -- "5. Request Financial Sync" --> T_Sync
    T_Sync -- "6. Send sync_request" --> WS_Server
    WS_Server -- "7. Relay to Master Phone" --> M_Sync
    M_Sync -- "8. Read All Years & Tables" --> M_DB
    M_Sync -- "9. SHA-256 Digest & Chunking" --> WS_Server
    WS_Server -- "10. In-Memory Relay (sync_data)" --> T_Sync
    T_Sync -- "11. Validate SHA-256 Digest" --> T_Sync
    T_Sync -- "12. Atomic Transaction (Rollback on error)" --> T_DB
    T_DB -- "13. Offline Data Available" --> T_UI
```

---

### 2. Component & Layer Interaction (Class / Component LLD)

```mermaid
classDiagram
    class DatabaseHelper {
        +Database database
        +createFinancialSnapshot() Map
        +createDeltaSnapshot(lastKnownIds) Map
        +importFinancialSnapshot(syncId, tables, digest) bool
        +importDeltaSnapshot(syncId, deltaTables, digest) bool
        +getTableRecordCounts() Map~String, int~
        +getLatestKnownIds() Map~String, int~
        -_assertCanAdd()
        -_assertCanEdit()
        -_assertCanDelete()
        -_assertCanSyncData()
    }

    class RemoteSyncService {
        +isMaster: bool
        +isSyncing: ValueNotifier~bool~
        +syncStatusText: ValueNotifier~String~
        +onSyncCompleted: Stream~Map~
        +initialize() void
        +requestSyncFromMaster(forceFull) Future~bool~
        +prepareSyncPackage() Future~Map~
        +prepareDeltaSyncPackage() Future~Map~
        +applySyncPackageSafely(package) Future~bool~
        +applyDeltaSyncPackageSafely(package) Future~bool~
        +formatCounts(counts) String
    }

    class SignalingService {
        +isConnected: bool
        +onMessage: Stream~Map~
        +connect() void
        +registerClient(role, deviceId, ...) void
        +sendSyncRequest(...) void
        +sendSyncData(...) void
        +sendSyncChunk(...) void
        +sendSyncAck(...) void
    }

    class AuthService {
        +currentUser: KhajaniUser?
        +isLoggedIn: bool
        +isDeveloper: bool
        +isLatestKhajani: bool
        +isOldKhajani: bool
        +canView: bool
        +canAdd: bool
        +canEdit: bool
        +canDelete: bool
        +canSearch: bool
        +canPdf: bool
        +canSync: bool
    }

    class DeviceService {
        +getDeviceId() Future~String~
        +getDeviceName() Future~String~
    }

    class AnnualPdfGenerator {
        +generateAnnualPdf(year) Future~Uint8List~
        +getAnnualReportSummary(year) Future~ReportData~
    }

    RemoteSyncService --> DatabaseHelper : Reads/Writes Snapshot
    RemoteSyncService --> SignalingService : Transmits Packages & Chunks
    RemoteSyncService --> AuthService : Verifies View/Sync Permissions
    RemoteSyncService --> DeviceService : Reads Hardware Device ID
    DatabaseHelper --> AuthService : Granular Operation Guard
    AnnualPdfGenerator --> DatabaseHelper : Reads Local SQLite (100% Offline)
```

---

### 3. Device Approval & Financial Sync Sequence Diagram

```mermaid
sequenceDiagram
    autonumber
    actor Target as Target Phone (New/Old)
    participant Relay as PC Signaling Server (Relay)
    actor Dev as Developer Phone
    actor Master as Master Phone (Latest Khajani)

    %% Step 1: Device Approval
    Target->>Relay: Register & Send Device Request (Device ID, Name, Role)
    Relay->>Dev: Push Device Request Notification
    Dev->>Relay: Submit Approval (Role: OLD_KHAJANI, Permissions: View, Search, PDF)
    Relay->>Target: Deliver Approval Result

    %% Step 2: Financial Sync
    Note over Target: Approval Received -> Trigger Auto Sync
    Target->>Relay: sync_request (requesterDeviceId, isDelta, lastKnownIds)
    Relay->>Master: Forward sync_request to Master

    Note over Master: [SYNC_STARTED] -> [MASTER_DATA_READ]
    Master->>Master: Read all 7 financial tables (all years)
    Note over Master: [DATA_SERIALIZED] -> SHA-256 Checksum Calculation
    Master->>Relay: sync_data / sync_chunks (snapshot, digest, counts)
    Note over Relay: [SERVER_RECEIVED] -> Relayed in-memory (No Disk Save)
    Relay->>Target: Relay sync_data / sync_chunks

    Note over Target: [TARGET_RECEIVED] -> [DATA_VALIDATED]
    Target->>Target: Verify SHA-256 Payload Digest
    Note over Target: [SQLITE_TRANSACTION_STARTED]
    Target->>Target: Insert/Update Records (ConflictAlgorithm.replace)
    Note over Target: [DATA_INSERTED/UPDATED] -> [SQLITE_COMMITTED]
    Target->>Relay: Send sync_ack (status: SUCCESS)
    Relay->>Master: Relay sync_ack
    Note over Target: [SYNC_COMPLETED] -> [UI_REFRESHED]
    Note over Target: Dashboard, Tables & Offline PDF Ready
```

---

### 4. Database Schema & Entity-Relationship (ER) Diagram

```mermaid
erDiagram
    KHAJANI_USERS {
        string user_id PK
        string name
        string password_hash
        string salt
        string role "DEVELOPER | LATEST_KHAJANI | OLD_KHAJANI"
        int is_active
        string status "PENDING | APPROVED | REJECTED | REVOKED"
        int can_view
        int can_add
        int can_edit
        int can_delete
        int can_search
        int can_pdf
        int can_sync
        int created_at
        int updated_at
    }

    DEVICE_REQUESTS {
        string request_id PK
        string user_id
        string user_name
        string device_id
        string device_name
        string request_type
        string status
        string requested_role
        int created_at
        int updated_at
    }

    REGISTERED_DEVICES {
        string device_id PK
        string device_name
        string user_id
        string status
        int created_at
        int updated_at
        int last_seen_at
    }

    VARGANI {
        int id PK
        string name
        real amount
        string date
        int year
    }

    PRASAD_DENGANI {
        int id PK
        string name
        real amount
        string date
        int year
    }

    PRASAD_SAHITYA {
        int id PK
        string name
        string item
        real amount
        string date
        int year
    }

    AARTI_VARGANI {
        int id PK
        string name
        real amount
        string date
        int year
    }

    KHARCH {
        int id PK
        string title
        real amount
        string date
        string category
        int year
    }

    MAHAPRASAD_KHARCH {
        int id PK
        string title
        real amount
        string date
        int year
    }

    PREVIOUS_BALANCE {
        int year PK
        real balance
    }

    APP_META {
        string key PK
        string value
    }

    KHAJANI_USERS ||--o{ DEVICE_REQUESTS : submits
    KHAJANI_USERS ||--o{ REGISTERED_DEVICES : binds
```

---

## 🔄 Comprehensive Debug Log Pipeline

During remote synchronization, both Master and Target logs output exact actual database counts:

```text
[SYNC_STARTED] requestId=sync_1741234567 requester=D-NEW-PHONE user=khajani_02
[MASTER_DATA_READ] Vargani: 150 records, Prasad Dengani: 40 records, Prasad Sahitya: 15 records, Aarti Vargani: 10 records, Kharch: 80 records, Mahaprasad Kharch: 25 records, Previous Balance: 5 records
[DATA_SERIALIZED] Vargani: 150 records, Prasad Dengani: 40 records, Kharch: 80 records...
[DATA_SENT] to=D-NEW-PHONE, Vargani: 150 records...
[SERVER_RECEIVED] from=D-MASTER to=D-NEW-PHONE (Relaying in-memory without disk save)
[TARGET_RECEIVED] from=D-MASTER, Vargani: 150 records...
[DATA_VALIDATED] Vargani: 150 records...
[SQLITE_TRANSACTION_STARTED] Vargani: 150 records...
[DATA_INSERTED/UPDATED] Vargani: 150 records, Prasad Dengani: 40 records, Kharch: 80 records...
[SQLITE_COMMITTED] Vargani: 150 records, Prasad Dengani: 40 records, Kharch: 80 records...
[SYNC_COMPLETED] Vargani: 150 records, Prasad Dengani: 40 records, Kharch: 80 records...
[UI_REFRESHED] Vargani: 150 records, Prasad Dengani: 40 records, Kharch: 80 records...
```

---

## 🔒 Security & Data Integrity Guarantees

1. **Transaction Safety & Rollback:**
   - Any corruption or network interruption during sync aborts the atomic SQLite transaction. The existing local database remains unaltered.
2. **Duplicate Prevention:**
   - Database operations use `ConflictAlgorithm.replace` with original primary keys preserved, ensuring idempotent syncs.
3. **Chunking Mechanism:**
   - Large database packages are broken into 32 KB chunks to operate smoothly across restrictive WebSocket connections and ngrok tunnels.
4. **Offline First:**
   - Internet/server connectivity is required only during the sync operation. Once saved in local SQLite, table viewing, Marathi search, and annual report PDF generation function completely offline.
5. **Layered Authorization:**
   - `OLD_KHAJANI` accounts with read-only permissions have Add/Edit/Delete blocked at both the UI level and the `DatabaseHelper` repository layer (`_assertCanAdd()`, `_assertCanEdit()`, `_assertCanDelete()`).

---

## 🚀 Running the Server & Application

### 1. Start the PC Signaling Server

Using the provided batch scripts:
```cmd
"Start Server.cmd"
```
Or run directly using Dart:
```sh
dart run server/signaling_server.dart
```
Or run using Python:
```sh
python server/signaling_server.py
```

### 2. Run the Flutter App

```sh
flutter pub get
flutter run
```

### 3. Run Quality & Test Suite

Verify all 118 unit, widget, and end-to-end sync tests:
```sh
flutter analyze
flutter test
```

---

## 📁 Storage Directory Structure (Android)

- **Active Database:** `/storage/emulated/0/हिंदवी/hindvi_latest.db`
- **Recovery & Backup:** `/storage/emulated/0/हिंदवी/Old/`
