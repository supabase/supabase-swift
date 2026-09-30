//
//  KnownProviders.swift
//  Examples
//
//  Created by Guilherme Souza on 13/08/26.
//

import Supabase

/// OAuth providers this demo app offers in its provider pickers.
///
/// `Provider` isn't `CaseIterable` — Auth accepts any provider string, including ones the SDK
/// doesn't have a static constant for yet — so this app-level list stands in for what
/// `Provider.allCases` used to provide, scoped to the example app rather than the SDK's public API.
let knownProviders: [Provider] = [
  .apple, .azure, .bitbucket, .discord, .email, .facebook, .figma, .github, .gitlab, .google,
  .kakao, .keycloak, .linkedin, .linkedinOIDC, .notion, .slack, .slackOIDC, .spotify, .twitch,
  .twitter, .x, .workos, .zoom, .fly,
]
