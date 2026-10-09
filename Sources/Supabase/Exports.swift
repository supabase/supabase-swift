//
//  Exports.swift
//  Supabase
//
//  Created by Guilherme Souza on 30/05/25.
//

// `@_spi(Experimental)` re-exports the experimental API (Auth's passkeys, PostgREST's typed queries)
// alongside the public API, so consumers can opt in with `@_spi(Experimental) import Supabase`.
@_spi(Experimental) @_exported import Auth
@_exported import Functions
@_spi(Experimental) @_exported import PostgREST
@_exported import Realtime
@_exported import Storage
