//! The shell on a device (see ./lib.rs).
use kagamizo_shell::App;

#[cfg(not(target_arch = "wasm32"))]
fn main() -> eframe::Result<()> {
    use eframe::egui;
    let target = std::env::var("KAGAMIZO_TARGET").unwrap_or_else(|_| "yoga-c940".into());
    let app = App::new(&target);
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_title("Kagamizo")
            .with_app_id("kagamizo-shell")
            .with_fullscreen(true),
        ..Default::default()
    };
    eframe::run_native("Kagamizo", options, Box::new(move |_| Ok(Box::new(app))))
}

#[cfg(target_arch = "wasm32")]
fn main() {}
