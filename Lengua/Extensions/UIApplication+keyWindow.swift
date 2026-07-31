import Foundation
import SwiftUI

extension UIApplication {
  public var keyWindow: UIWindow? {
    Self
      .shared
      .connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .last { $0.isKeyWindow }
  }

  public var keyWindowPresentedController: UIViewController? {
    var viewController = keyWindow?.rootViewController

    if let presentedController = viewController as? UITabBarController {
      viewController = presentedController.selectedViewController
    }

    while let presentedController = viewController?.presentedViewController {
      if let presentedController = presentedController as? UITabBarController {
        viewController = presentedController.selectedViewController
      } else {
        viewController = presentedController
      }
    }
    return viewController
  }
}
