import Flutter
import UIKit

/// `ghost_md/day` on the iPhone: a day picked from the phone's own calendar (lib/core/phone_day.dart), as
/// android/…/ghost_md/DayPick.kt is on Android. What a hidden `<input type="date">` and its `showPicker()` were to
/// the real app's Pick a date (tauri/ `editor/fieldMenu.ts` `pickDay`), where the iPhone's WebView answered with
/// its own calendar.
///
/// - `pick {current}` -> the day chosen as `YYYY-MM-DD`, or null when the calendar was left without one. `current`
///   is the day it opens on, in the same form; today where it is missing or is not a day.
///
/// The calendar is `UIDatePicker`'s, in the phone's own language and its light or dark, in a sheet half the
/// screen's height with Cancel and Done. It has no Clear, which the WebView's had (Reset): a field's own cross
/// clears it, as on Android.
final class DayChannel: NSObject, UIAdaptivePresentationControllerDelegate {
  private var channel: FlutterMethodChannel?
  private var asking: FlutterResult?
  private weak var sheet: UIViewController?
  private weak var calendar: UIDatePicker?

  init(messenger: FlutterBinaryMessenger) {
    super.init()
    let channel = FlutterMethodChannel(name: "ghost_md/day", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "pick" else { return result(FlutterMethodNotImplemented) }
      self?.pick((call.arguments as? [String: Any])?["current"] as? String, result)
    }
    self.channel = channel
  }

  /// `YYYY-MM-DD` on the phone's own calendar's days, whatever its language or its calendar's kind.
  private static let days: DateFormatter = {
    let format = DateFormatter()
    format.calendar = Calendar(identifier: .gregorian)
    format.locale = Locale(identifier: "en_US_POSIX")
    format.dateFormat = "yyyy-MM-dd"
    return format
  }()

  private func answer(_ day: String?) {
    guard let asking = asking else { return }
    self.asking = nil
    asking(day)
  }

  private func pick(_ current: String?, _ result: @escaping FlutterResult) {
    // One calendar at a time: a second ask puts the first away, unanswered but for a null.
    sheet?.dismiss(animated: false)
    answer(nil)
    guard let over = GhostChannels.presenter() else { return result(nil) }
    asking = result

    let picker = UIDatePicker()
    picker.datePickerMode = .date
    picker.preferredDatePickerStyle = .inline
    if let current = current, let day = DayChannel.days.date(from: current) { picker.date = day }
    picker.translatesAutoresizingMaskIntoConstraints = false
    calendar = picker

    let page = UIViewController()
    page.view.backgroundColor = .systemBackground
    page.view.addSubview(picker)
    NSLayoutConstraint.activate([
      picker.topAnchor.constraint(equalTo: page.view.safeAreaLayoutGuide.topAnchor),
      picker.leadingAnchor.constraint(equalTo: page.view.layoutMarginsGuide.leadingAnchor),
      picker.trailingAnchor.constraint(equalTo: page.view.layoutMarginsGuide.trailingAnchor),
    ])
    page.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelled))
    page.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(chosen))

    let framed = UINavigationController(rootViewController: page)
    framed.modalPresentationStyle = .pageSheet
    if let presentation = framed.sheetPresentationController {
      presentation.detents = [.medium(), .large()]
      presentation.prefersGrabberVisible = true
    }
    framed.presentationController?.delegate = self
    sheet = framed
    over.present(framed, animated: true)
  }

  @objc private func chosen() {
    let day = calendar.map { DayChannel.days.string(from: $0.date) }
    sheet?.dismiss(animated: true)
    answer(day)
  }

  @objc private func cancelled() {
    sheet?.dismiss(animated: true)
    answer(nil)
  }

  // Swiped away.
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    answer(nil)
  }
}
