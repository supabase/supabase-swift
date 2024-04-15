# Migration Guides

## v2.x to v3.x

### Realtime

On v3.x `RealtimeClientV2` became the standard entry point to the Realtime funcionality, `RealtimeClientV2` got renamed to `RealtimeClient`.

The same was done with `RealtimeChannelV2`, `PresenceV2`, and `RealtimeMessagelV2`.

On `SupabaseClient`, the `realtimeV2` attribute got replaced with `realtime`.

Applying changes above, you can follow https://github.com/supabase/supabase-swift/blob/main/docs/migrations/RealtimeV2%20Migration%20Guide.md