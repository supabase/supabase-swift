import SupabaseStorage
import XCTest

@testable import Supabase

final class SupabaseTests: XCTestCase {
    var supabase = Supabase(supabaseUrl: SupabaseTests.supabaseUrl(), supabaseKey: SupabaseTests.supabaseKey())
    
    static func supabaseUrl() -> String {
        if let token = ProcessInfo.processInfo.environment["supabaseUrl"] {
            return token
        } else {
            fatalError()
        }
    }
    
    static func supabaseKey() -> String {
        if let url = ProcessInfo.processInfo.environment["supabaseKey"] {
            return url
        } else {
            fatalError()
        }
    }
    
    func testSignIN() {
        let e = expectation(description: "testSignIN")
        
        supabase.auth.signIn(email: "sample@mail.com", password: "secret") { result in
            switch result {
            case let .success(session):
                print(session)
                XCTAssertNotNil(session.accessToken)
            case let .failure(error):
                print(error.localizedDescription)
                XCTFail("testSignIN failed: \(error.localizedDescription)")
            }
            e.fulfill()
        }
        
        waitForExpectations(timeout: 30) { error in
            if let error = error {
                XCTFail("testSignIN failed: \(error.localizedDescription)")
            }
        }
    }
    
    func testListBuckets() {
        let e = expectation(description: "listBuckets")
        
        supabase.storage.listBuckets { result in
            switch result {
            case let .success(buckets):
                XCTAssertEqual(buckets.count >= 0, true)
            case let .failure(error):
                print(error.localizedDescription)
                XCTFail("listBuckets failed: \(error.localizedDescription)")
            }
            e.fulfill()
        }
        
        waitForExpectations(timeout: 30) { error in
            if let error = error {
                XCTFail("listBuckets failed: \(error.localizedDescription)")
            }
        }
    }
    
    func testUploadFile() {
        let e = expectation(description: "testUploadFile")
        let data = try! Data(
            contentsOf: URL(
                string: "https://raw.githubusercontent.com/satishbabariya/storage-swift/main/README.md")!)
        
        let file = File(name: "README.md", data: data, fileName: "README.md", contentType: "text/html")
        
        supabase.storage.from(id: "Demo").upload(
            path: "\(UUID().uuidString).md", file: file, fileOptions: FileOptions(cacheControl: "3600")
        ) { result in
            switch result {
            case let .success(res):
                print(res)
                XCTAssertEqual(true, true)
            case let .failure(error):
                print(error.localizedDescription)
                XCTFail("testUploadFile failed: \(error.localizedDescription)")
            }
            e.fulfill()
        }
        
        waitForExpectations(timeout: 30) { error in
            if let error = error {
                XCTFail("testUploadFile failed: \(error.localizedDescription)")
            }
        }
    }
}
