//
//  Exports.swift
//  Helpers
//
//  Created by Guilherme Souza on 09/09/26.
//

// Every module re-exports Helpers, so this puts `HTTPRequest`, `HTTPResponse`, `HTTPFields` and
// `HTTPField.Name` in scope for anyone implementing ``ClientTransport`` or ``ClientMiddleware``
// with a single `import Supabase`. HTTPTypesFoundation adds the `URL`/`URLRequest` bridges
// (`HTTPRequest.url`, `URLRequest(httpRequest:)`) those implementations reach for.
@_exported public import HTTPTypes
@_exported public import HTTPTypesFoundation
