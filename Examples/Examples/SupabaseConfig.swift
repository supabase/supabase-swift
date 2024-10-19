import Foundation

enum SupabaseConfig {
  static subscript(key: String) -> String? {
    guard let plistFileURL = Bundle.main.url(forResource: "Supabase", withExtension: "plist"),
      let plistData = try? Data(contentsOf: plistFileURL),
      let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil)
        as? [String: Any]
    else { return nil }

    return plist[key] as? String
  }
}
