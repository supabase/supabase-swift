# Examples

This directory contains example applications demonstrating the usage of Supabase Swift SDK.

## Prerequisites

[Requirements](../README.md#requirements)

## Running the Examples App

1. Open the `Examples.xcodeproj` file in Xcode
2. Select your target device or simulator
3. Build and run the project (⌘R)

## Authentication Setup

### Supabase Credentials Setup

The examples app uses a local Supabase instance by default. To set up your Supabase credentials:

1. Open `Supabase.plist` in the Examples project
2. Update the following values:
   - `SUPABASE_URL`: Your Supabase project URL
   - `SUPABASE_ANON_KEY`: Your Supabase project's anon/public key

You can find these values in your Supabase project dashboard under Project Settings > API.

### Google Sign-In Setup

To enable Google Sign-In in the examples app:

1. Create a project in the [Google Cloud Console](https://console.cloud.google.com/)
2. Enable the Google Sign-In API
3. Create OAuth 2.0 credentials for iOS
4. Update the `Info.plist` file with your credentials:
   - Replace `{{ YOUR_IOS_CLIENT_ID }}` with your iOS client ID
   - Replace `{{ YOUR_SERVER_CLIENT_ID }}` with your server client ID
   - Replace `{{ DOT_REVERSED_IOS_CLIENT_ID }}` with your reversed client ID

### Facebook Sign-In Setup

To enable Facebook Sign-In in the examples app:

1. Create an app in the [Facebook Developers Console](https://developers.facebook.com/)
2. Add iOS platform to your Facebook app
3. Update the `Info.plist` file with your Facebook credentials:
   - Replace `{{ FACEBOOK APP ID }}` with your Facebook App ID
   - Replace `{{ FACEBOOK CLIENT TOKEN }}` with your Facebook Client Token
