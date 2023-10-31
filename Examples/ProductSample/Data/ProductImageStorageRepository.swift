//
//  ProductImageStorageRepository.swift
//  ProductSample
//
//  Created by Guilherme Souza on 19/10/23.
//

import Foundation
import Storage

protocol ProductImageStorageRepository: Sendable {
  func uploadImage(_ params: ImageUploadParams) async throws -> String
  func downloadImage(_ key: ImageKey) async throws -> Data
}

struct ProductImageStorageRepositoryImpl: ProductImageStorageRepository {
  let storage: SupabaseStorageClient

  func uploadImage(_ params: ImageUploadParams) async throws -> String {
    let fileName = "\(params.fileName).\(params.fileExtension ?? "png")"
    let contentType = params.mimeType ?? "image/png"
    let imagePath = try await storage.from(id: "product-images")
      .upload(
        path: fileName,
        file: File(
          name: fileName, data: params.data, fileName: fileName, contentType: contentType
        ),
        fileOptions: FileOptions(contentType: contentType, upsert: true)
      )
    return imagePath
  }

  func downloadImage(_ key: ImageKey) async throws -> Data {
    // we save product images in the format "bucket-id/image.png", but SupabaseStorage prefixes
    // the path with the bucket-id already so we must provide only the file name to the download
    // call, this is what lastPathComponent is doing below.
    let fileName = (key.rawValue as NSString).lastPathComponent
    return try await storage.from(id: "product-images").download(path: fileName)
  }
}
