//
//  StorageObjectTests.swift
//  Storage
//
//  Created by Guilherme Souza on 09/10/26.
//

import Foundation
import Testing

@testable import Storage

@Suite
struct StorageObjectTests {
  @Test
  func decodesAListingRowWithTypedMetadata() throws {
    let json = Data(
      """
      {
        "name": "sadcat.jpg",
        "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
        "version": "v2",
        "updated_at": "2024-01-02T03:04:05.000Z",
        "created_at": "2024-01-01T00:00:00.000Z",
        "last_accessed_at": null,
        "metadata": {
          "eTag": "\\"abc\\"",
          "size": 28834,
          "mimetype": "image/jpeg",
          "cacheControl": "max-age=3600",
          "lastModified": "2024-01-02T03:04:05.000Z",
          "contentLength": 28834,
          "httpStatusCode": 200
        },
        "user_metadata": {"value": 42},
        "is_versioned": true,
        "is_delete_marker": false
      }
      """.utf8)

    let object = try JSONDecoder.storage.decode(StorageObject.self, from: json)

    #expect(object.id == UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
    #expect(object.version == "v2")
    #expect(!object.isFolder)
    #expect(object.metadata?.eTag == "\"abc\"")
    #expect(object.metadata?.size == 28834)
    #expect(object.metadata?.mimeType == "image/jpeg")
    #expect(object.metadata?.cacheControl == "max-age=3600")
    #expect(object.metadata?.lastModified == object.updatedAt)
    #expect(object.metadata?.contentLength == 28834)
    #expect(object.metadata?.additional == ["httpStatusCode": 200])
    #expect(object.userMetadata == ["value": 42])
    #expect(object.isVersioned == true)
    #expect(object.isDeleteMarker == false)
    #expect(object.lastAccessedAt == nil)
  }

  @Test
  func decodesAFolderRow() throws {
    let json = Data(
      """
      {"name": "folder", "id": null, "updated_at": null, "created_at": null, "last_accessed_at": null, "metadata": null}
      """.utf8)

    let object = try JSONDecoder.storage.decode(StorageObject.self, from: json)

    #expect(object.isFolder)
    #expect(object.metadata == nil)
    #expect(object.version == nil)
  }

  @Test
  func metadataToleratesAnUnparsableLastModified() throws {
    let json = Data(#"{"size": 1, "lastModified": "yesterday"}"#.utf8)

    let metadata = try JSONDecoder.storage.decode(ObjectMetadata.self, from: json)

    #expect(metadata.size == 1)
    #expect(metadata.lastModified == nil)
    #expect(metadata.additional.isEmpty)
  }

  @Test
  func decodesObjectInfo() throws {
    let json = Data(
      """
      {
        "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
        "version": "v1",
        "name": "folder/sadcat.jpg",
        "bucket_id": "avatars",
        "size": 28834,
        "content_type": "image/jpeg",
        "cache_control": "max-age=3600",
        "etag": "\\"abc\\"",
        "last_modified": "2024-01-02T03:04:05.000Z",
        "created_at": "2024-01-01T00:00:00.000Z",
        "metadata": {"value": 42}
      }
      """.utf8)

    let info = try JSONDecoder.storage.decode(ObjectInfo.self, from: json)

    #expect(info.id == UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
    #expect(info.bucketId == "avatars")
    #expect(info.size == 28834)
    #expect(info.contentType == "image/jpeg")
    #expect(info.eTag == "\"abc\"")
    #expect(info.lastModified != nil)
    #expect(info.userMetadata == ["value": 42])
    #expect(info.updatedAt == nil)
  }
}
