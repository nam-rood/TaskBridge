# TaskBridge

[中文](./README.md) | English

TaskBridge is a macOS menu bar app that provides bidirectional sync between Feishu Tasks and Apple Reminders.

If your team relies on Feishu Tasks for collaboration, but your personal workflow is built around Reminders on macOS, iPhone, or Apple Watch, TaskBridge bridges the gap:

- Sync Feishu tasks into Apple Reminders
- Push local Reminder changes back to Feishu tasks
- Keep your Apple-native workflow without losing the Feishu collaboration layer

> The project is still in an early stage. It is strongly recommended to test with a dedicated Feishu app, a test account, or a small set of tasks before using it with real work data.

## Who this is for

TaskBridge is a good fit if you want to:

- Use Apple Reminders personally while your team requires Feishu Tasks
- View and complete Feishu tasks directly from iPhone or Apple Watch
- Pull Feishu tasks into a system-level Apple workflow
- Preserve Feishu task list structure while working locally in a more native interface

## Features

Current capabilities include:

- Feishu OAuth login
- Feishu Tasks → Apple Reminders sync
- Apple Reminders → Feishu Tasks sync
- Sync for task title, completion state, and due date
- Mapping of Feishu task lists / sections to Apple reminder lists
- Automatic sync on app startup
- Retry sync after wake from sleep
- Background sync every 120 seconds
- Automatic push-back when local Reminders change
- Automatic refresh of expired Feishu tokens
- Local SQLite storage for mappings to avoid duplicate creation
- Menu bar app that does not occupy the Dock

## How it works

The overall flow looks like this:

1. Enter your Feishu `App ID` and `App Secret` in the app
2. Complete Feishu OAuth in the browser
3. Grant Apple Reminders permission
4. TaskBridge fetches tasks, task lists, and sections from Feishu
5. TaskBridge creates or updates matching reminder lists and reminders locally
6. Later changes from either side are synced back whenever possible

### Automatic sync triggers

TaskBridge attempts to sync in the following cases:

- Immediately after app launch, if authorization is already complete
- After the Mac wakes from sleep
- Every 120 seconds while the app is running
- After local Apple Reminders changes, following a short debounce

## Sync scope and rules

Understanding the sync rules helps avoid surprises.

### Feishu → Apple Reminders

TaskBridge reads Feishu tasks, task lists, and sections, then creates corresponding Apple reminder lists.

Default naming rules:

- Feishu task list: `飞书 - List Name`
- Feishu task list section: `飞书 - List Name - Section Name`
- Tasks with no list assignment: `飞书 - 我负责的`

Fields synced from Feishu to Apple:

- Task title
- Completion state
- Due date
- Task list / section assignment
- Deletion state, meaning that if a Feishu task is deleted, the matching local reminder is also deleted

### Apple Reminders → Feishu

Only reminders inside TaskBridge-managed lists are pushed back to Feishu. In practice, that usually means lists such as:

- `飞书 - List Name`
- `飞书 - List Name - Section Name`
- `飞书 - 我负责的`

Inside those lists, you can do the following directly in Apple Reminders:

- Create reminders
- Change titles
- Change completion state
- Change due dates
- Delete reminders

Those changes will be synced back to Feishu whenever possible.

### Conflict handling

TaskBridge is a practical bidirectional bridge, not a strongly consistent real-time collaboration system.

The current implementation relies on local sync snapshots and persisted mappings to infer which side changed. That means:

- It is best suited for personal productivity workflows
- It is not ideal for high-frequency, multi-user, multi-device concurrent editing of the same task
- If both Feishu and Apple modify the same field in a short period of time, the final result may depend on the most recently detected change

### Deduplication and mapping

To avoid duplicate tasks, TaskBridge stores the following in a local SQLite database:

- Feishu task ID ↔ Apple reminder ID mappings
- Feishu task list / section ↔ Apple reminder list mappings
- Snapshots of title, completion state, due date, and related sync metadata

This local state is the foundation that makes bidirectional sync possible.

## System requirements

- macOS 13.0 or later
- Xcode or a Swift toolchain for building and running from source
- A usable self-built Feishu Open Platform app
- Permission to access Apple Reminders

## Quick start

### 1. Clone the repository

```bash
git clone <your-repo-url>
cd TaskBridge
```

### 2. Build and run

The project uses Swift Package Manager.

Run in development mode:

```bash
swift run TaskBridge
```

Build only:

```bash
swift build
```

### 3. Package as a `.app`

```bash
./build_app.sh
open TaskBridge.app
```

If the script is not executable yet:

```bash
chmod +x build_app.sh
```

`build_app.sh` will:

- Run `swift build -c release`
- Create a standard macOS `.app` bundle structure
- Copy the executable and `Info.plist`
- Perform local codesigning on the app bundle to improve permission recognition by macOS

## Feishu app setup

TaskBridge does not rely on a hosted SaaS backend. Instead, you must use your own Feishu Open Platform app for OAuth authorization.

### 1. Create a self-built enterprise app in Feishu

Create a self-built enterprise app in the Feishu Open Platform and collect:

- App ID
- App Secret

`App ID` usually starts with `cli_`.

### 2. Configure the redirect URL whitelist

In the OAuth / security settings of your Feishu app, add the following redirect URL to the whitelist:

```text
http://127.0.0.1:21016/callback
```

TaskBridge starts a temporary local HTTP callback server to receive the Feishu OAuth result.

### 3. Grant the required permissions

Enable the task-related read/write permissions and the permission required to identify the current authorized user.

The current code uses capabilities such as:

- Read tasks
- Read task lists
- Read sections within task lists
- Create tasks
- Update tasks
- Delete tasks
- Read the current authorized user

Permission names may vary slightly across versions of the Feishu admin console. If authorization succeeds but the API still reports missing permissions, add the required scopes indicated by the error and make sure the app is properly published or enabled in the correct scope.

## First-time usage flow

For the first run, the recommended order is:

1. Start TaskBridge
2. Click the TaskBridge icon in the menu bar
3. Open the Settings window
4. Fill in the Feishu `App ID` and `App Secret`
5. Grant Apple Reminders permission when macOS prompts you
6. Click `Login with Feishu` and complete browser authorization
7. Return to TaskBridge and click `Sync Now` for the initial sync

Once both Reminders permission and Feishu login are ready, the app enters automatic sync mode.

## UI overview

TaskBridge is currently a menu bar-only app.

The menu bar panel mainly contains:

- Reminders authorization status
- Feishu login status
- A button to grant Reminders access
- A button to log in to or log out from Feishu
- A `Sync Now` button
- A Settings entry
- A Quit entry

The app does not appear in the Dock, which makes it suitable as a small background utility.

## Local data storage

TaskBridge stores sync-related local data on your machine:

- Sync database: `~/Library/Application Support/com.namrood.TaskBridge/taskbridge.sqlite`
- Feishu user tokens: `UserDefaults`
- Feishu `App ID` / `App Secret`: `UserDefaults`

By default, this data stays on your machine and is not uploaded anywhere except Feishu APIs.

### Legacy data migration

If you previously used the older project named `LarkFlow`, the current code attempts to migrate the old local database into the `TaskBridge` data directory so existing mappings can be preserved.

## Privacy and security notes

Please keep the following in mind:

- TaskBridge needs full Apple Reminders access in order to create, update, and delete reminders
- TaskBridge needs your Feishu OAuth authorization to access task data
- The current version stores `App ID`, `App Secret`, access tokens, and refresh tokens in local preferences rather than Keychain
- Because of that, building from source yourself is safer than using unknown binary releases
- If you stop using TaskBridge, it is a good idea to revoke Feishu authorization and clean up local data

## Troubleshooting

### 1. Feishu login does not return successfully

Check the following first:

- Whether `http://127.0.0.1:21016/callback` is configured correctly in the Feishu app
- Whether local port `21016` is already occupied by another process
- Whether the browser actually returns to the local callback page after authorization

If port `21016` is occupied, authorization currently fails because the callback port is fixed.

### 2. Reminders permission is granted, but sync still does not start

Make sure that:

- TaskBridge is allowed to access Reminders in macOS system settings
- The menu bar UI shows Reminders as authorized
- Feishu login has completed successfully

TaskBridge only starts automatic sync when both Reminders permission and Feishu login are available.

### 3. Feishu tasks do not appear in Apple Reminders

Check whether:

- Your Feishu app permissions are complete
- The authorized Feishu account actually has access to the expected task data
- You clicked `Sync Now` to trigger the first sync
- The menu bar UI shows a sync failure message

### 4. Reminders changed locally, but nothing was pushed back to Feishu

Make sure you modified reminders inside a TaskBridge-managed list rather than a normal personal list.

In practice, only reminders inside lists such as the following are pushed back:

- `飞书 - List Name`
- `飞书 - List Name - Section Name`
- `飞书 - 我负责的`

Also note that local changes go through a short debounce period before being uploaded.

### 5. Duplicate tasks appeared, or you want to reset sync

You can back up local data and then clean up:

- Delete `~/Library/Application Support/com.namrood.TaskBridge/taskbridge.sqlite`
- Delete the reminder lists created by TaskBridge
- Re-authorize and sync again

The repository also includes a helper script that removes all reminder lists whose titles start with `飞书 - `:

```bash
swift clear_reminders.swift
```

Please make sure those lists do not contain any local data you want to keep before using it.

## Current limitations

Known limitations of the current version:

- It mainly syncs title, completion state, due date, and task list / section assignment
- It does not yet sync task descriptions, comments, attachments, subtasks, or other advanced fields
- The OAuth callback port is fixed to local port `21016`
- There is no formal app signing, notarization, or distribution flow yet
- There is currently no dedicated conflict visualization UI
- Because the app relies on local state snapshots, it should not be treated as a strongly consistent collaboration system

## Development notes

### Dependencies

Main dependencies include:

- SwiftUI: menu bar UI
- AppKit: app lifecycle and window management
- EventKit: Apple Reminders integration
- Network: local OAuth callback server
- GRDB: local SQLite wrapper

### Project structure

```text
Sources/TaskBridge/
├── TaskBridge.swift               # App entry and startup logic
├── MenuBarContentView.swift       # Menu bar UI and user actions
├── SettingsView.swift             # Settings UI
├── SettingsWindowController.swift # Settings window controller
├── FeishuOAuthManager.swift       # Feishu OAuth login and token refresh
├── FeishuAPIClient.swift          # Feishu task API client
├── EventKitManager.swift          # Apple Reminders access wrapper
├── SyncEngine.swift               # Feishu -> Apple sync logic
├── AppleToFeishuSync.swift        # Apple -> Feishu sync logic
├── DatabaseManager.swift          # SQLite mappings and sync snapshot storage
└── TaskViewModel.swift            # Task data shaping
```

### Helper scripts

The repository root also contains a few debugging / maintenance scripts:

- `print_calendars.swift`: print reminder lists whose titles start with `飞书`
- `print_tasks.swift`: print reminders from a target list
- `clear_reminders.swift`: remove Feishu-related reminder lists created by TaskBridge

Example usage:

```bash
swift print_calendars.swift
swift print_tasks.swift
swift clear_reminders.swift
```

### Recommended validation during development

At minimum, run:

```bash
swift build
```

If you modify sync logic, it is recommended to manually verify:

- Whether newly created Feishu tasks appear in Apple Reminders
- Whether newly created local reminders are pushed to Feishu
- Whether title, completion state, and due date sync in both directions
- Whether deletion behavior matches expectations
- Whether task list / section mapping works correctly

## Contributing

Issues and pull requests are welcome.

If you plan to change sync logic, it helps to explain:

- Which sync direction is affected
- Which Feishu fields and Apple Reminders fields are involved
- Whether existing mappings or local data are affected
- Whether users need to re-authorize or clean up historical data

## License

This project is released under the MIT License.
