import Foundation

/// Reads the page number of every link in a `Link` response header, keyed by its `rel` value.
///
/// The header holds one link per relation, for example
/// `</admin/users?page=2>; rel="next", </admin/users?page=3>; rel="last"`.
///
/// Links that do not parse or carry no page number are skipped, so a header the client cannot read
/// costs the pagination metadata rather than failing a request that otherwise succeeded.
func parsePaginationLinks(_ header: String?) -> [String: Int] {
  guard let header,
    let pattern = try? NSRegularExpression(pattern: #"<([^>]+)>\s*;\s*rel="([^"]+)""#)
  else { return [:] }

  var pages: [String: Int] = [:]
  let matches = pattern.matches(in: header, range: NSRange(header.startIndex..., in: header))

  for match in matches {
    guard let uri = Range(match.range(at: 1), in: header).map({ String(header[$0]) }),
      let rel = Range(match.range(at: 2), in: header).map({ String(header[$0]) }),
      let page = URLComponents(string: uri)?.queryItems?.first(where: { $0.name == "page" })?.value,
      let pageNumber = Int(page)
    else { continue }

    pages[rel] = pageNumber
  }

  return pages
}
