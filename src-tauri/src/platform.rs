//! What one platform's window needs that Tauri does not do for it: on iOS, a
//! window made key so the keyboard can rise; on macOS, the traffic lights set
//! into the page's taller title bar. Each is called once from `setup`, and on
//! every other platform this module is empty.

/// Makes the app's window the key window once the scene has attached it.
///
/// Under the scene lifecycle (UIApplicationSupportsMultipleScenes, which iOS
/// 26+ forces on this app), tao attaches its window to the scene but nothing
/// ever calls `makeKeyAndVisible` - and a window that is not KEY cannot host a
/// first responder. The visible symptom is exactly Apple's QA1813: taps land
/// (buttons work, focus rings draw) but the keyboard never rises, because the
/// text field's becomeFirstResponder is silently refused. For a notes app that
/// is the whole app not working. Asserted twice on a delay because the scene
/// connect that creates the window races setup, and re-asserting on an
/// already-key window is a no-op.
#[cfg(target_os = "ios")]
pub fn ensure_key_window(handle: &tauri::AppHandle) {
    let handle = handle.clone();
    std::thread::spawn(move || {
        for delay_ms in [600u64, 2200] {
            std::thread::sleep(std::time::Duration::from_millis(delay_ms));
            let _ = handle.run_on_main_thread(|| unsafe {
                use objc2::msg_send;
                use objc2::runtime::{AnyClass, AnyObject};
                let Some(app_class) = AnyClass::get(c"UIApplication") else {
                    return;
                };
                let shared: *mut AnyObject = msg_send![app_class, sharedApplication];
                if shared.is_null() {
                    return;
                }
                let key: *mut AnyObject = msg_send![shared, keyWindow];
                if !key.is_null() {
                    return;
                }
                let windows: *mut AnyObject = msg_send![shared, windows];
                if windows.is_null() {
                    return;
                }
                let first: *mut AnyObject = msg_send![windows, firstObject];
                if first.is_null() {
                    return;
                }
                let () = msg_send![first, makeKeyAndVisible];
            });
        }
    });
}

/// Centres the native traffic lights in the page's taller custom title bar
/// (tauri-plugin-decorum). macOS lays them out again on every resize, so they
/// are put back then too.
#[cfg(target_os = "macos")]
pub fn place_traffic_lights(app: &tauri::App) {
    use tauri::Manager;
    use tauri_plugin_decorum::WebviewWindowExt;
    if let Some(main) = app.get_webview_window("main") {
        const INSET: (f32, f32) = (16.0, 30.0);
        let _ = main.set_traffic_lights_inset(INSET.0, INSET.1);
        let win = main.clone();
        main.on_window_event(move |event| {
            if matches!(event, tauri::WindowEvent::Resized(_)) {
                let _ = win.set_traffic_lights_inset(INSET.0, INSET.1);
            }
        });
    }
}
