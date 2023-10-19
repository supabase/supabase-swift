//
//  ImageUploadUseCase.swift
//  ProductSample
//
//  Created by Guilherme Souza on 19/10/23.
//

import Foundation
import Storage

protocol ImageUploadUseCase: UseCase<ImageUploadParams, Task<String, Error>> {}

struct ImageUploadUseCaseImpl: ImageUploadUseCase {
  let storage: SupabaseStorageClient

  func execute(input: ImageUploadParams) -> Task<String, Error> {
    Task {
      let fileName = "\(input.fileName).\(input.fileExtension ?? "png")"
      let contentType = input.mimeType ?? "image/png"
      let imagePath = try await storage.from(id: "product-images")
        .upload(
          path: fileName,
          file: File(
            name: fileName, data: input.data, fileName: fileName, contentType: contentType),
          fileOptions: FileOptions(contentType: contentType, upsert: true)
        )
      return imagePath
    }
  }
}
