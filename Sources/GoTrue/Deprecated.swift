import Foundation

extension GoTrueMetaSecurity {
  @available(*, deprecated, renamed: "captchaToken")
  public var hcaptchaToken: String {
    get { captchaToken }
    set { captchaToken = newValue }
  }

  @available(*, deprecated, renamed: "init(captchaToken:)")
  public init(hcaptchaToken: String) {
    self.init(captchaToken: hcaptchaToken)
  }
}
