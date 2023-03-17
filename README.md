# supabase-swift

Supabase client for swift. Mirrors the design of [supabase-js](https://github.com/supabase/supabase-js/blob/master/README.md).

## Contents
- [Installation](#installation)
- [Usage](#usage)
- [Login Implementation](#login-implementation)
- [Social Login Implementation](#social-login-implementation)
    - [Setup Callback URL](#setup-callback-url)
    - [Google Sign In](#google-sign-in)
    - [Apple Sign In](#apple-sign-in)
    - [Other Social Logins](#other-social-logins)
- [Basic CRUD Implementation](#basic-crud-implementation)
    - [Insert Data](#insert-data)
    - [Select Data](#select-data)
- [Contributing](#contributing)
- [Sponsors](#sponsors)

---

## Installation

Swift Package Manager:

Add the following lines to your `Package.swift` file:
```swift
let package = Package(
    ...
    dependencies: [
        ...
        .package(name: "Supabase", url: "https://github.com/supabase/supabase-swift.git", branch: "master"), // Add the package
    ],
    targets: [
        .target(
            name: "YourTargetName",
            dependencies: ["Supabase"] // Add as a dependency
        )
    ]
)
```

If you're using Xcode, [use this guide](https://developer.apple.com/documentation/swift_packages/adding_package_dependencies_to_your_app) to add `supabase-swift` to your project. Use `https://github.com/supabase/supabase-swift.git` for the url when Xcode asks.

## Usage

To make requests to the `Supabase` database, you will need to initialize a `SupabaseClient` object:

```swift
let client = SupabaseClient(supabaseURL: "{ Supabase URL }", supabaseKey: "{ Supabase anonymous Key }")
```

## Login Implementation

Inside the `SupabaseClient` instance created before, you can find an `auth` property of type `GoTrueClient`. You can use it to perform sign in and sign up requests.

- Here's how to sign up with an email and password and get the signed in user `Session` info:

```swift
Task {
  do {
      try await client.auth.signUp(email: email, password: password)
      let session = try await client.auth.session
      print("### Session Info: \(session)") 
  } catch {
      print("### Sign Up Error: \(error)")
  }
}
```

- For existing users, here's how to log in with an email and password and get the logged in user `Session` info:

```swift
Task {
  do {
      try await client.auth.signIn(email: email, password: password)
      let session = try await client.auth.session
      print("### Session Info: \(session)") 
  } catch {
      print("### Sign Up Error: \(error)")
  }
}
```

## Social Login Implementation

### Setup Callback URL

We need to first set up the callback URL for all Social Logins inside the app.

- Setup the callback `URL` on `Info.plist`:

```xml
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>app.yourapp://login-callback</string>
        </array>
    </dict>
</array>
```

- Add this callback `URL` on `Supabase` under `Authentication -> URL Configuration -> Redirect URLs`.

### Google Sign In

- Setup Google Auth as per [Supabase's Documentation](https://supabase.com/docs/guides/auth/social-login/auth-google).
- Note: For iOS we still need to use Google Consent Form for Web.
- Import `SafariServices` in your `ViewController` and create a `SFSafariViewController` instance:

```swift
import SafariServices

var safariVC: SFSafariViewController?
```

- Get the `URL` for Google Sign in from `Supabase` and load it on `SFSafariViewController`.
- Pass the previous callback `URL` you set up in the `redirecTo` parameter:

```swift
Task {
    do {
        let url = try await client.auth.getOAuthSignInURL(provider: Provider.google, redirectTo: URL(string: {Your Callback URL})!)
        safariVC = SFSafariViewController(url: url as URL)
        self.present(safariVC!, animated: true, completion: nil)
    } catch {
        print("### Google Sign in Error: \(error)")
    }
}
```

- Handle the callback `URL` on `SceneDelegate` (for older projects, you can use `AppDelegate` if `SceneDelegate` is not present).
- Post a `NotificationCenter` call to let the `ViewController` know the callback has been fired and pass the `URL` received. This `URL` will be used to get the user session.

```swift
func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    if let url = URLContexts.first?.url as? URL {
        if url.host == "login-callback" {
            let urlDict: [String: URL] = ["url": url]
            NotificationCenter.default.post(name: Notification.Name("OAuthCallBack"), object: nil, userInfo: urlDict)
        }
    }
}
```

- In your `ViewController`, observe for the `Notification` and handle it minimizing the `SFSafariViewController` and getting the session:

```swift
NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.oAuthCallback(_:)),
            name: NSNotification.Name(rawValue: "OAuthCallBack"),
            object: nil)
            
@objc func oAuthCallback(_ notification: NSNotification){
    guard let url = notification.userInfo?["url"] as? URL  else { return }
    Task {
        do {
            let session = try await SupaBaseAuth().client.session(from: url)
            print("### Session Info: \(session)")
        } catch {
            print("### oAuthCallback error: \(error)")
        }
    }
    safariVC?.dismiss(animated: true)
}
```

### Apple Sign In

- Setup Apple Auth as per [Supabase's Documentation](https://supabase.com/docs/guides/auth/social-login/auth-apple). 
- For Sign in with Apple follow the above as per Google Sign In and just replace the provider.
- Once the user moves to the `SFSafariViewController`, an Apple native pop-up will slide up to continue with the sign in.

```swift
Task {
    do {
        let url = try await client.auth.getOAuthSignInURL(provider: **Provider.apple**, redirectTo: URL(string: {Your Callback URL})!)
        safariVC = SFSafariViewController(url: url as URL)
        self.present(safariVC!, animated: true, completion: nil)
    } catch {
        print("### Apple Sign in Error: \(error)")
    }
}
```

### Other Social Logins

- If using a WebViews, other social logins will be similar to above. Just follow the [Supabase's Documentation](https://supabase.com/docs/guides/auth/) for their setup.

## Basic CRUD Implementation

First, import and initialize `SupabaseClient`, as explained in "Usage" section.

### Insert Data

- Create a model which follows your table's data structure:

```swift
struct InsertModel: Encodable, Decodable {
    let id: Int? // you can choose to omit this depending on how you've setup your table
    let title: String?
    let desc: String?
}

let insertData = InsertModel(title: "Test", desc: "Test Desc")
let query = client.database
            .from("{ Your Table Name }")
            .insert(values: insertData,
                    returning: .representation) // you will need to add this to return the added data
            .select(columns: "id") // specifiy which column names to be returned. Leave it empty for all columns
            .single() // specify you want to return a single value.
            
Task {
    do {
        let response: [InsertModel] = try await query.execute().value
        print("### Returned: \(response)")
    } catch {
        print("### Insert Error: \(error)")
    }
}
```

### Select Data

- Using the same model as before:

```swift
let insertData = InsertModel(title: "Test", desc: "Test Desc")
let query = client.database
            .from("{ Your Table Name }")
            .select() // keep it empty for all, else specify returned data
            .match(query: ["title" : insertData.title, "desc": insertData.desc])
            .single()
            
Task {
    do {
        let response: [InsertModel] = try await query.execute().value
        print("### Returned: \(response)")
    } catch {
        print("### Insert Error: \(error)")
    }
}
```

## Contributing

- Fork the repo on GitHub
- Clone the project to your own machine
- Commit changes to your own branch
- Push your work back up to your fork
- Submit a Pull request so that we can review your changes and merge

## Sponsors

We are building the features of Firebase using enterprise-grade, open source products. We support existing communities wherever possible, and if the products don’t exist we build them and open source them ourselves. Thanks to these sponsors who are making the OSS ecosystem better for everyone.

[![New Sponsor](https://user-images.githubusercontent.com/10214025/90518111-e74bbb00-e198-11ea-8f88-c9e3c1aa4b5b.png)](https://github.com/sponsors/supabase)
