//
//  ImageTransformView.swift
//  Examples
//
//  Demonstrates image transformation capabilities (resize, quality, format)
//

import Supabase
import SwiftUI

struct ImageTransformView: View {
  @State private var selectedBucket = ""
  @State private var buckets: [Bucket] = []
  @State private var imagePath = ""
  @State private var transformedImage: UIImage?
  @State private var originalImage: UIImage?
  @State private var error: Error?
  @State private var isLoading = false

  // Transform options
  @State private var width: String = "400"
  @State private var height: String = "400"
  @State private var quality: Double = 80
  @State private var resizeMode: ResizeMode = .cover
  @State private var format: ImageFormat = .original

  enum ResizeMode: String, CaseIterable {
    case cover = "cover"
    case contain = "contain"
    case fill = "fill"

    var description: String {
      switch self {
      case .cover:
        return "Cover - Maintains aspect ratio, fills dimensions"
      case .contain:
        return "Contain - Maintains aspect ratio, fits within dimensions"
      case .fill:
        return "Fill - Stretches to fill dimensions"
      }
    }
  }

  enum ImageFormat: String, CaseIterable {
    case original = "original"
    case webp = "webp"

    var value: String? {
      self == .original ? nil : rawValue
    }
  }

  var body: some View {
    List {
      Section {
        Text("Transform images on-the-fly with resize, quality, and format options")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section("Select Image") {
        if buckets.isEmpty {
          Text("Loading buckets...")
            .foregroundColor(.secondary)
        } else {
          Picker("Bucket", selection: $selectedBucket) {
            Text("Select a bucket").tag("")
            ForEach(buckets) { bucket in
              Text(bucket.name).tag(bucket.id)
            }
          }
        }

        TextField("Image path (e.g., folder/photo.jpg)", text: $imagePath)
          .textInputAutocapitalization(.never)
      }

      Section("Transformation Options") {
        HStack {
          Text("Width")
          Spacer()
          TextField("400", text: $width)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 80)
          Text("px")
        }

        HStack {
          Text("Height")
          Spacer()
          TextField("400", text: $height)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 80)
          Text("px")
        }

        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("Quality")
            Spacer()
            Text("\(Int(quality))%")
              .foregroundColor(.secondary)
          }
          Slider(value: $quality, in: 20...100, step: 10)
        }

        Picker("Resize Mode", selection: $resizeMode) {
          ForEach(ResizeMode.allCases, id: \.self) { mode in
            Text(mode.rawValue.capitalized).tag(mode)
          }
        }

        Picker("Format", selection: $format) {
          ForEach(ImageFormat.allCases, id: \.self) { fmt in
            Text(fmt.rawValue.capitalized).tag(fmt)
          }
        }
      }

      Section {
        Button("Transform & Download") {
          Task {
            await downloadWithTransform()
          }
        }
        .disabled(selectedBucket.isEmpty || imagePath.isEmpty || isLoading)

        Button("Download Original (No Transform)") {
          Task {
            await downloadOriginal()
          }
        }
        .disabled(selectedBucket.isEmpty || imagePath.isEmpty || isLoading)
      }

      if isLoading {
        Section {
          ProgressView("Processing image...")
        }
      }

      // Original Image
      if let originalImage {
        Section("Original Image") {
          VStack(spacing: 8) {
            Image(uiImage: originalImage)
              .resizable()
              .scaledToFit()
              .frame(maxHeight: 200)
              .cornerRadius(8)

            Text("Size: \(originalImage.size.width)×\(originalImage.size.height)")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      }

      // Transformed Image
      if let transformedImage {
        Section("Transformed Image") {
          VStack(spacing: 8) {
            Image(uiImage: transformedImage)
              .resizable()
              .scaledToFit()
              .frame(maxHeight: 200)
              .cornerRadius(8)
              .overlay(
                RoundedRectangle(cornerRadius: 8)
                  .stroke(Color.accentColor, lineWidth: 2)
              )

            Text("Size: \(transformedImage.size.width)×\(transformedImage.size.height)")
              .font(.caption)
              .foregroundColor(.secondary)

            Text("\(resizeMode.rawValue) • Quality: \(Int(quality))%")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      }

      if let error {
        Section {
          ErrorText(error)
        }
      }

      Section("Code Examples") {
        CodeExample(
          code: """
            // Download with transformations
            let data = try await supabase.storage
              .from("my-bucket")
              .download(
                path: "images/photo.jpg",
                options: TransformOptions(
                  width: \(width),
                  height: \(height),
                  resize: "\(resizeMode.rawValue)",
                  quality: \(Int(quality))\(format != .original ? ",\n      format: \"\(format.rawValue)\"" : "")
                )
              )

            let image = UIImage(data: data)
            """
        )

        CodeExample(
          code: """
            // Get public URL with transformations
            let url = try supabase.storage
              .from("my-bucket")
              .getPublicURL(
                path: "images/photo.jpg",
                options: TransformOptions(
                  width: 300,
                  height: 300,
                  resize: "cover",
                  quality: 85
                )
              )

            // Load image from URL
            """
        )
      }

      Section("Resize Mode Details") {
        ForEach(ResizeMode.allCases, id: \.self) { mode in
          VStack(alignment: .leading, spacing: 4) {
            Text(mode.rawValue.capitalized)
              .font(.headline)
            Text(mode.description)
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      }
    }
    .navigationTitle("Image Transforms")
    .task {
      await loadBuckets()
    }
  }

  @MainActor
  func loadBuckets() async {
    do {
      buckets = try await supabase.storage.listBuckets()
      if let firstBucket = buckets.first {
        selectedBucket = firstBucket.id
      }
    } catch {
      self.error = error
    }
  }

  @MainActor
  func downloadOriginal() async {
    do {
      error = nil
      transformedImage = nil
      isLoading = true
      defer { isLoading = false }

      let data = try await supabase.storage
        .from(selectedBucket)
        .download(path: imagePath)

      if let image = UIImage(data: data) {
        originalImage = image
      }
    } catch {
      self.error = error
    }
  }

  @MainActor
  func downloadWithTransform() async {
    do {
      error = nil
      transformedImage = nil
      isLoading = true
      defer { isLoading = false }

      let options = TransformOptions(
        width: Int(width),
        height: Int(height),
        resize: resizeMode.rawValue,
        quality: Int(quality),
        format: format.value
      )

      let data = try await supabase.storage
        .from(selectedBucket)
        .download(path: imagePath, options: options)

      if let image = UIImage(data: data) {
        transformedImage = image
      }
    } catch {
      self.error = error
    }
  }
}
