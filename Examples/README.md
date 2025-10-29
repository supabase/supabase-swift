# Supabase Swift Examples

A comprehensive SwiftUI application demonstrating all features of the Supabase Swift SDK with best-in-class UX and extensive inline code examples.

## Overview

This example app serves as both a functional demonstration and an educational resource for developers learning the Supabase Swift SDK. Each feature includes:

- 🎯 **Interactive Examples**: Try every SDK feature with real data
- 📝 **Inline Code Snippets**: See exact API usage within each screen
- 📚 **Educational Content**: Detailed explanations and use cases
- ✨ **Modern UX**: Polished interface following iOS design patterns
- 🔄 **Live Updates**: Real-time feedback and state management

## Features Showcased

### 🔐 Authentication

Comprehensive authentication examples with multiple sign-in methods:

- **Email & Password**: Traditional sign-up and sign-in with email confirmation
- **Magic Link**: Passwordless authentication via email
- **Phone OTP**: SMS-based authentication with verification codes
- **OAuth Providers**:
  - Sign in with Apple (native integration)
  - Sign in with Google (using Google Sign-In SDK)
  - Sign in with Facebook
  - Generic OAuth flow for other providers
- **Anonymous Sign-In**: Temporary guest access with account conversion
- **Multi-Factor Authentication (MFA)**:
  - TOTP enrollment with QR codes
  - Authenticator app support
  - Factor management and verification

Each auth method includes:
- Step-by-step guidance
- Loading states and error handling
- Success confirmations
- Code examples showing exact API usage

### 💾 Database (PostgREST)

Full-featured database operations with a todo list example:

- **CRUD Operations**: Create, read, update, and delete todos
- **Filtering & Ordering**: Advanced query filters and sorting options
- **RPC Functions**: Call custom PostgreSQL functions
- **Aggregations**: Count and aggregate data operations
- **Relationships**: Query related data across tables with joins

Features:
- Real-time todo list with instant updates
- Inline SQL examples
- Filter builder with multiple conditions
- Relationship demonstrations with profiles

### ⚡️ Realtime

Live data synchronization across multiple channels:

- **Postgres Changes**: Listen to database INSERT, UPDATE, DELETE events
- **Broadcast**: Send and receive real-time messages between clients
- **Presence**: Track online users with metadata
- **Live Todo Updates**: See changes from other users instantly

Features:
- Connection status indicators
- Message history
- Online user count
- Automatic reconnection

### 📦 Storage

Complete file and bucket management system:

- **Bucket Operations**:
  - Create, update, delete buckets
  - Configure public/private access
  - Set file size limits
  - Empty buckets

- **File Upload**:
  - Photo library integration
  - Document picker
  - Multiple upload methods
  - Progress tracking
  - Upsert support

- **File Download**:
  - Download with preview
  - Image display
  - Text file viewing
  - Metadata inspection

- **Image Transformations**:
  - Resize (width/height)
  - Quality adjustment
  - Format conversion (WebP)
  - Multiple resize modes (cover, contain, fill)
  - Side-by-side comparison

- **Signed URLs**:
  - Temporary download links
  - Signed upload URLs
  - Public URL generation
  - Expiration control

- **File Management**:
  - Move files between paths
  - Copy files
  - Delete single/multiple files
  - Batch operations

- **Search & Metadata**:
  - Advanced file search
  - Sort by name, date, size
  - Filter by type
  - Detailed metadata view

All storage examples include inline code snippets showing the exact API calls.

### 🚀 Edge Functions

Serverless function invocation:

- Invoke Edge Functions
- Pass parameters
- Handle responses
- Error management

### 👤 User Profile Management

Comprehensive user account management:

- **Profile Overview**:
  - View account information
  - Email, phone, user ID
  - Account creation date
  - MFA status indicator

- **Update Profile**:
  - Change email (with verification)
  - Update phone number (with OTP)
  - Change password
  - Multi-field updates

- **Password Management**:
  - Password reset via email
  - Secure reset links
  - Step-by-step recovery flow

- **Linked Identities**:
  - View all linked OAuth accounts
  - Link new social providers
  - Unlink identities
  - Provider icons and metadata
  - Swipe-to-delete gesture

- **Security**:
  - MFA enrollment and management
  - Reauthentication
  - Session management
  - Sign out (global/local)

Features:
- Pull-to-refresh
- Loading states
- Success/error feedback
- Inline code examples
- Educational tooltips

## Prerequisites

- Xcode 16.0 or later
- iOS 17.0+ / macOS 14.0+ or later
- [Supabase CLI](https://supabase.com/docs/guides/cli) installed

## Setup Instructions

### 1. Start Local Supabase Instance

The Examples app is configured to use a local Supabase instance from the `/supabase` directory.

```bash
# Navigate to the root directory
cd /path/to/supabase-swift

# Start Supabase local development
supabase start
```

This will start the local Supabase services:
- **API**: http://127.0.0.1:54321
- **Studio**: http://127.0.0.1:54323
- **Inbucket** (email testing): http://127.0.0.1:54324

### 2. Database Setup

The database schema is automatically created from migrations in `/supabase/migrations/`:

- `20240327182636_init_key_value_storage_schema.sql` - Key-value storage
- `20251009000000_examples_schema.sql` - Examples app tables and RLS policies

These migrations are applied automatically when you run `supabase start`.

**Optional**: Seed sample data:
```bash
# Load seed data into the database
supabase db reset
```

### 3. Configuration

The app is pre-configured to use the local instance:

**Supabase.plist:**
```xml
<dict>
  <key>SUPABASE_URL</key>
  <string>http://127.0.0.1:54321</string>
  <key>SUPABASE_ANON_KEY</key>
  <string>eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0</string>
</dict>
```

This is the default anon key for local Supabase development.

### 4. Running the App

1. Open `Examples.xcodeproj` in Xcode
2. Ensure local Supabase is running (`supabase start`)
3. Select your target device or simulator
4. Build and run (⌘R)

### 5. Using the App

#### First Time Setup
1. **Sign Up**: Create an account using any authentication method
   - Try email/password for the full experience
   - Or use "Sign in Anonymously" for quick testing

2. **Explore the Tabs**:

   **Database Tab**:
   - Create your first todo
   - Try filtering and ordering
   - Test RPC functions
   - View aggregations

   **Realtime Tab**:
   - Watch database changes live
   - Send broadcast messages
   - Join presence channels
   - See other users online (open app in multiple simulators!)

   **Storage Tab**:
   - Create a bucket
   - Upload images from Photos
   - Try image transformations
   - Generate signed URLs
   - Search and manage files

   **Functions Tab**:
   - Invoke sample Edge Functions
   - Test with different parameters

   **Profile Tab**:
   - View your account details
   - Update email/phone/password
   - Link social accounts
   - Enable MFA for extra security
   - Manage linked identities

#### Testing Real-time Features

For the best real-time experience:
1. Open the app on multiple devices/simulators
2. Sign in with different accounts
3. Navigate to the Realtime tab
4. Watch updates appear instantly across all devices

#### Testing Email Features

Use Inbucket to view test emails:
1. Open http://127.0.0.1:54324
2. Sign up with any email (e.g., test@example.com)
3. Check Inbucket for confirmation emails
4. Click magic links or copy verification codes

## OAuth Provider Setup (Optional)

To test OAuth authentication, you'll need to configure providers:

### Google Sign-In

1. Create a project in [Google Cloud Console](https://console.cloud.google.com/)
2. Enable Google Sign-In API
3. Create OAuth 2.0 credentials for iOS
4. Update `Info.plist`:
   - Replace `{{ YOUR_IOS_CLIENT_ID }}`
   - Replace `{{ YOUR_SERVER_CLIENT_ID }}`
   - Replace `{{ DOT_REVERSED_IOS_CLIENT_ID }}`

### Facebook Sign-In

1. Create an app in [Facebook Developers Console](https://developers.facebook.com/)
2. Add iOS platform
3. Update `Info.plist`:
   - Replace `{{ FACEBOOK APP ID }}`
   - Replace `{{ FACEBOOK CLIENT TOKEN }}`

### Apple Sign-In

Apple Sign-In should work out of the box on iOS devices. Ensure:
- Sign in with Apple capability is enabled in Xcode
- Proper bundle identifier is configured

## Project Structure

```
Examples/
├── Examples/
│   ├── Auth/              # Authentication examples
│   │   ├── AuthExamplesView.swift           # Main auth navigation
│   │   ├── AuthWithEmailAndPassword.swift   # Email/password auth
│   │   ├── AuthWithMagicLink.swift          # Magic link auth
│   │   ├── SignInWithPhone.swift            # Phone OTP auth
│   │   ├── SignInAnonymously.swift          # Anonymous auth
│   │   ├── SignInWithApple.swift            # Apple Sign In
│   │   ├── SignInWithFacebook.swift         # Facebook auth
│   │   ├── SignInWithOAuth.swift            # Generic OAuth
│   │   └── GoogleSignInSDKFlow.swift        # Google Sign-In SDK
│   │
│   ├── Database/          # PostgREST database examples
│   │   ├── DatabaseExamplesView.swift       # Main database navigation
│   │   ├── TodoListView.swift               # CRUD operations
│   │   ├── FilteringView.swift              # Query filtering
│   │   ├── RPCExamplesView.swift            # RPC functions
│   │   ├── AggregationsView.swift           # Aggregations
│   │   └── RelationshipsView.swift          # Joins and relations
│   │
│   ├── Realtime/          # Realtime subscriptions
│   │   ├── RealtimeExamplesView.swift       # Main realtime navigation
│   │   ├── PostgresChangesView.swift        # Database changes
│   │   ├── TodoRealtimeView.swift           # Live todo updates
│   │   ├── BroadcastView.swift              # Broadcast messages
│   │   └── PresenceView.swift               # Online presence
│   │
│   ├── Storage/           # File storage examples
│   │   ├── StorageExamplesView.swift        # Main storage navigation
│   │   ├── BucketOperationsView.swift       # Bucket CRUD
│   │   ├── FileUploadView.swift             # File uploads
│   │   ├── FileDownloadView.swift           # File downloads
│   │   ├── ImageTransformView.swift         # Image transformations
│   │   ├── SignedURLsView.swift             # URL generation
│   │   ├── FileManagementView.swift         # Move/copy/delete
│   │   └── FileSearchView.swift             # Search and metadata
│   │
│   ├── Functions/         # Edge Functions examples
│   │   └── FunctionsExamplesView.swift      # Function invocation
│   │
│   ├── Profile/           # User profile management
│   │   ├── ProfileView.swift                # Profile overview
│   │   ├── UpdateProfileView.swift          # Update credentials
│   │   ├── ResetPasswordView.swift          # Password reset
│   │   └── UserIdentityList.swift           # Linked accounts
│   │
│   ├── MFAFlow.swift      # Multi-factor authentication
│   ├── HomeView.swift     # Main tab navigation
│   ├── RootView.swift     # App root (auth check)
│   └── Shared/            # Shared utilities
│       ├── Components/    # Reusable UI components
│       └── Helpers/       # Helper functions
│
└── supabase/              # Local Supabase configuration
    ├── config.toml        # Supabase configuration
    ├── migrations/        # Database migrations
    │   ├── 20240327182636_init_key_value_storage_schema.sql
    │   └── 20251009000000_examples_schema.sql
    ├── seed.sql          # Seed data
    └── functions/        # Edge Functions
```

## Database Schema

The app uses the following tables with Row Level Security enabled:

### todos
```sql
CREATE TABLE todos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  description text NOT NULL,
  is_complete boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  owner_id uuid REFERENCES auth.users(id) ON DELETE CASCADE
);
```

RLS Policies:
- Users can only view/modify their own todos
- Authenticated users can create todos

### profiles
```sql
CREATE TABLE profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username text UNIQUE,
  full_name text,
  avatar_url text,
  website text,
  updated_at timestamptz DEFAULT now()
);
```

RLS Policies:
- All users can view profiles
- Users can only update their own profile

### messages
```sql
CREATE TABLE messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  content text NOT NULL,
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  channel_id text NOT NULL,
  created_at timestamptz DEFAULT now()
);
```

RLS Policies:
- All authenticated users can view messages
- Users can only insert/delete their own messages

### PostgreSQL Functions

**increment_todo_count()**
```sql
CREATE FUNCTION increment_todo_count(user_id uuid)
RETURNS integer;
```

Demonstrates RPC functionality with return values.

## Key Features & Patterns

### Inline Code Examples

Every screen includes `CodeExample` components showing the exact API calls:

```swift
CodeExample(
  code: """
    // Create a todo
    try await supabase
      .from("todos")
      .insert(Todo(description: "Learn Supabase"))
      .execute()
    """
)
```

### Educational Content

Each feature includes an "About" section explaining:
- What the feature does
- When to use it
- Best practices
- Security considerations

### Modern UX Patterns

- **Pull-to-refresh** for data updates
- **Swipe actions** for delete/unlink
- **Loading states** with descriptive messages
- **Error handling** with clear feedback
- **Success confirmations** with helpful next steps
- **Empty states** with guidance
- **Disclosure groups** for advanced details

### State Management

Consistent use of `ActionState` enum for async operations:
```swift
enum ActionState<Success, Failure: Error> {
  case idle
  case inFlight
  case result(Result<Success, Failure>)
}
```

### Reusable Components

- `ExampleRow`: Navigation items with icons and descriptions
- `CodeExample`: Syntax-highlighted code snippets
- `ErrorText`: Consistent error display
- `DetailRow`: Key-value information display

## Troubleshooting

### Supabase not running
```bash
# Check status
supabase status

# Restart services
supabase stop
supabase start
```

### Connection errors
- Ensure local Supabase is running on port 54321
- Check firewall settings
- Verify `Supabase.plist` has correct URL
- Try accessing Studio at http://127.0.0.1:54323

### Auth redirect issues
- Ensure custom URL scheme is configured: `com.supabase.swift-examples://`
- Check Info.plist for proper URL types configuration
- Verify redirect URL matches in Supabase config

### Database errors
- Run migrations: `supabase db reset`
- Check Studio at http://127.0.0.1:54323
- Verify RLS policies are correct
- Check user permissions

### Storage errors
- Ensure bucket exists before uploading
- Check bucket permissions (public vs private)
- Verify file size limits
- Test with Storage browser in Studio

### Real-time not working
- Check connection status in the app
- Verify Realtime is enabled in Studio
- Check RLS policies allow access
- Try reconnecting from the UI

## Using with Remote Supabase

To connect to a remote Supabase project:

### 1. Update Configuration

Update `Supabase.plist`:
```xml
<key>SUPABASE_URL</key>
<string>https://your-project.supabase.co</string>
<key>SUPABASE_ANON_KEY</key>
<string>your-anon-key</string>
```

### 2. Apply Migrations

```bash
# Link to your project
supabase link --project-ref your-project-ref

# Push migrations to remote
supabase db push

# Optional: Load seed data
supabase db reset --db-url "your-database-url"
```

### 3. Configure OAuth (if needed)

In your Supabase project settings:
1. Navigate to Authentication → Providers
2. Enable and configure OAuth providers
3. Add redirect URLs for your app

### 4. Configure Storage

1. Create buckets in Studio
2. Set up RLS policies
3. Configure CORS if needed

## Learning Resources

### In-App Learning

- **Code Examples**: Every screen has inline code showing API usage
- **About Sections**: Detailed explanations of each feature
- **Interactive Testing**: Try features with live data
- **Error Messages**: Learn from mistakes with clear feedback

### External Resources

- [Supabase Swift Documentation](https://supabase.com/docs/reference/swift)
- [Supabase Documentation](https://supabase.com/docs)
- [Swift SDK GitHub](https://github.com/supabase/supabase-swift)
- [Supabase Discord](https://discord.supabase.com)

## Tips for Developers

1. **Start Simple**: Begin with email/password auth and basic CRUD
2. **Use Code Examples**: Copy-paste examples directly into your app
3. **Test Locally First**: Use local Supabase for development
4. **Check RLS Policies**: Security is enabled by default
5. **Use Studio**: Visual tools help understand database state
6. **Enable Realtime**: More engaging user experience
7. **Add MFA**: Extra security for sensitive operations
8. **Test Edge Cases**: Try errors, empty states, slow connections

## Contributing

This example app is part of the Supabase Swift SDK. Contributions are welcome!

- Report issues on [GitHub](https://github.com/supabase/supabase-swift/issues)
- Submit pull requests for improvements
- Share feedback in [Discord](https://discord.supabase.com)

## License

This example app is part of the Supabase Swift SDK and follows the same [MIT License](../LICENSE).
