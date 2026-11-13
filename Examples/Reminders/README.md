# Reminders

A SwiftUI clone of the iOS Reminders app. A local Supabase stack is the backend.

The app shows how the parts of Supabase work together in one real app:

| Feature in the app | Supabase product |
|---|---|
| Sign up, sign in, stored session | Auth |
| Lists and reminders, smart lists, search | Database (PostgREST) with Row Level Security |
| Changes from other people show at once | Realtime (`postgres_changes`) |
| Share a list by email, accept or decline | Database functions (RPC) |
| Images on a reminder | Storage (private bucket) |

The app works only while the device is online. It has no local cache.

## Requirements

- Xcode 26 or later (supabase-swift v3 needs Swift 6.2)
- Docker, or a tool that is compatible with Docker
- Supabase CLI 3.1 or later
- For the UI tests: [Maestro](https://maestro.dev) 2.12 or later, and `jq`

Install Maestro from its own tap. The Homebrew formula named `maestro` is a different
product.

```bash
brew install mobile-dev-inc/tap/maestro
```

## Run the app

1. Start the backend. The first start downloads the Docker images.

   ```bash
   cd Examples/Reminders
   supabase start
   ```

2. Open `Supabase.xcworkspace` from the repository root.
3. Select the `Reminders` scheme and an iOS simulator. Run.
4. Sign up with an email address and a password. The local stack does not send an email.

The app connects to `http://127.0.0.1:54421`. The URL and the publishable key of the
local stack are in [App/Config.swift](App/Config.swift). The stack uses ports
54420–54429, so it can run at the same time as a stack on the default ports.

To try sharing, sign up a second account. A second simulator shows the changes of the
first one in real time.

Stop the backend with `supabase stop`.

## Backend

### Schema

The files in [supabase/schemas](supabase/schemas) are the source of truth. This project
uses Declarative Schemas with pg-delta, which is an experimental feature of the CLI.
`config.toml` turns it on:

```toml
[experimental.pgdelta]
enabled = true
```

To change the schema:

1. Edit a file in `supabase/schemas/`.
2. Write the migration:

   ```bash
   supabase db schema declarative sync -f <migration_name> --no-apply
   ```

3. Read the new file in `supabase/migrations/`.
4. Apply all migrations to a clean database:

   ```bash
   supabase db reset
   ```

5. Run the database tests:

   ```bash
   supabase test db
   ```

### Access rules

- Each table has Row Level Security. `anon` has no access.
- A list is open to its owner and its members. Only the owner can delete it or remove
  other members.
- The policies call `security definer` functions in the `private` schema, for example
  `private.has_list_access`. The API does not expose this schema.
- `authenticated` gets grants only on the columns that the app writes. The server owns
  columns such as `owner_id`, `created_by` and `updated_at`.
- A file in the `attachments` bucket has the path `{reminder id}/{file id}.jpg`. The
  Storage policies read the reminder id from the path.

### Sharing

The owner invites a person by email address. The invited person sees the invitation in
the app and accepts or declines it. The functions `my_invitations`, `accept_invitation`
and `decline_invitation` do this work, because the invited person cannot read the list
before they accept.

> [!IMPORTANT]
> The local config turns off email confirmation. A real project must turn it on.
> If it is off, a person can sign up with the email address of another person and
> accept the invitations sent to that address.

## App

```
App/
  RemindersApp.swift     Builds the SupabaseClient
  Config.swift           URL and publishable key of the local stack
  Supabase/              Models and repositories. Every database and Storage call is here
  Stores/                @Observable state: data, network, smart lists
  Features/              One folder for each screen
  Shared/                Root view, error alert, list colors and icons
```

- **Repositories** (`ListsRepository`, `RemindersRepository`, `SharingRepository`,
  `AttachmentsRepository`) make the PostgREST, RPC and Storage calls.
- **`AuthModel`** (from the SDK) follows the auth state. `RootView` switches on its
  `status`. The views call `client.auth` to sign in, sign up and sign out. The one
  `SupabaseClient` reaches the views through the `\.supabase` environment value.
- **`DataStore`** keeps all rows in memory. It loads them after sign-in and keeps them
  current from one Realtime channel
  ([DataStore+Realtime.swift](App/Stores/DataStore+Realtime.swift)).

### Writes

- An insert or a delete changes the screen after the server confirms it.
- An update is optimistic. `DataStore.optimisticUpdate` changes the row in memory, sends
  the update, and puts the old row back if the server refuses it.
- While an update of a row is in flight, the store ignores Realtime updates for that
  row. This stops the echo of an older edit from replacing a newer one.
- The details sheet sends only the fields that the user changed. A change that another
  person made while the sheet was open stays.

### Sync

- The app subscribes to Realtime first and loads the rows second. A change that arrives
  while the load runs makes the load read again, so the screen never goes back to an
  older state.
- Realtime sends delete events to all clients, with the primary key only. The app
  ignores a delete event for a row that it does not show.
- When a person moves a reminder to a list that the user cannot read, Realtime sends no
  event. The reminder goes away at the next load, or when the user changes it.

### Dates

A reminder can have a date with no time. That is a calendar day, not a moment. The app
saves it as 00:00 UTC of the day and reads the day back in the time zone of the device
(`Reminder.storedDay`, `Reminder.localDueDate`). Each person then sees the same day.

## Tests

### Database tests (pgTAP)

```bash
cd Examples/Reminders
supabase test db
```

The tests in [supabase/tests](supabase/tests) check the access rules as the owner, a
member, a stranger and an invited person.

### UI tests (Maestro)

```bash
Examples/Reminders/maestro/run.sh
```

The script resets the local database, builds the app, installs it on the simulator and
runs each flow in [maestro/flows](maestro/flows). To run one flow:

```bash
Examples/Reminders/maestro/run.sh Examples/Reminders/maestro/flows/sharing.yaml
```

Environment variables:

| Variable | Use |
|---|---|
| `SIMULATOR` | Simulator name. Default: `iPhone 18 Pro` |
| `SKIP_BUILD=1` | Use the last build |
| `SKIP_RESET=1` | Keep the database as it is |

Some flows change data from outside the app, to act as a second person. They call the
REST API with the secret key of the local stack. The script reads the key from
`supabase status` at run time. Do not write this key in a file.

The debug build has one launch argument for tests: `-failUpdates YES` makes each update
fail, so that a flow can check the rollback of an optimistic update.

## Limits

- No offline mode and no local cache.
- No subtasks, sections, tags, repeating reminders or notifications.
- No invitation email. The invited person must open the app.
- If the app stops between a file upload and the insert of its row, the file stays in
  the bucket with no row.
