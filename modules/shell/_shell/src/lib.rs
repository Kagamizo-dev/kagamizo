//! kagamizo-shell: the home and settings of every Kagamizo target
//! (modules/shell), natively on a NixOS image and as WebAssembly in the
//! browser. The declarations are fixed at build time (SHELL_DECLARED); a
//! device's target is KAGAMIZO_TARGET, set by its session; the browser's is
//! `web`. Keys: up and down move through the column, enter opens, escape
//! goes back; in settings, left and right move between the section list
//! and its rows.
pub mod model;

use eframe::egui::{
    self, Align, Color32, CornerRadius, Frame, Key as EKey, Layout, Margin, RichText, Sense, Stroke,
};
pub use model::{Effect, Key, Kind, Screen, Shell};

pub const DECLARED: &str = include_str!(env!("SHELL_DECLARED"));

// The palette: ink, paper and one accent.
const INK: Color32 = Color32::from_rgb(0x12, 0x14, 0x18);
const CARD: Color32 = Color32::from_rgb(0x1c, 0x20, 0x27);
const RAISED: Color32 = Color32::from_rgb(0x26, 0x2c, 0x36);
const PAPER: Color32 = Color32::from_rgb(0xe8, 0xe6, 0xe1);
const MUTED: Color32 = Color32::from_rgb(0x9a, 0x9f, 0xa8);
const ACCENT: Color32 = Color32::from_rgb(0x6f, 0xc3, 0xb2);

pub struct App {
    pub shell: Shell,
    pub target: String,
    pub note: String,
    pub web: bool,
    /// Whether a key moved the focus this frame, so the view follows it
    /// (a tap leaves the scroll where the finger put it).
    pub moved: bool,
}

impl App {
    pub fn new(target: &str) -> App {
        let declared: model::Declared =
            serde_json::from_str(DECLARED).expect("the shell's declarations");
        App {
            shell: Shell::new(declared, target),
            target: target.into(),
            note: String::new(),
            web: target == "web",
            moved: false,
        }
    }
}

impl App {
    fn keys(&mut self, ctx: &egui::Context) {
        let pressed: Vec<Key> = ctx.input(|i| {
            [
                (EKey::ArrowUp, Key::Up),
                (EKey::ArrowDown, Key::Down),
                (EKey::ArrowLeft, Key::Left),
                (EKey::ArrowRight, Key::Right),
                (EKey::Enter, Key::Enter),
                (EKey::Escape, Key::Back),
                (EKey::Backspace, Key::Back),
            ]
            .into_iter()
            .filter(|(k, _)| i.key_pressed(*k))
            .map(|(_, k)| k)
            .collect()
        });
        self.moved = !pressed.is_empty();
        for k in pressed {
            let e = self.shell.key(k, self.web);
            self.apply(e);
        }
    }

    fn apply(&mut self, e: Effect) {
        match e {
            Effect::None => {}
            Effect::Open(url) => self.note = open(&url),
            Effect::Run(cmd) => self.note = run(&cmd),
        }
    }

    fn home(&mut self, ui: &mut egui::Ui) {
        ui.add_space(24.0);
        ui.label(RichText::new("Kagamizo").size(30.0).color(PAPER).strong());
        ui.label(RichText::new(&self.target).size(15.0).color(MUTED));
        ui.add_space(24.0);
        let mut tapped = None;
        egui::ScrollArea::vertical().show(ui, |ui| {
            let mut shelf = "";
            for (i, (_, a)) in self.shell.apps.iter().enumerate() {
                // A shelf for each category, headed by its name.
                if a.category != shelf {
                    shelf = &a.category;
                    ui.add_space(if i == 0 { 0.0 } else { 12.0 });
                    ui.label(
                        RichText::new(shelf.to_uppercase())
                            .size(13.0)
                            .color(MUTED)
                            .strong(),
                    );
                    ui.add_space(8.0);
                }
                let focused = i == self.shell.focus;
                let frame = Frame::new()
                    .fill(if focused { RAISED } else { CARD })
                    .corner_radius(CornerRadius::same(14))
                    .inner_margin(Margin::symmetric(24, 18))
                    .stroke(if focused {
                        Stroke::new(2.0_f32, ACCENT)
                    } else {
                        Stroke::new(2.0_f32, CARD)
                    });
                let r = frame.show(ui, |ui| {
                    ui.set_width(ui.available_width());
                    ui.label(
                        RichText::new(&a.name)
                            .size(if focused { 26.0 } else { 22.0 })
                            .color(PAPER),
                    );
                    let sub = if a.description.is_empty() {
                        kind_label(&a.kind)
                    } else {
                        a.description.as_str()
                    };
                    ui.label(RichText::new(sub).size(14.0).color(if focused {
                        ACCENT
                    } else {
                        MUTED
                    }));
                });
                let r = r.response.interact(Sense::click());
                if r.clicked() {
                    tapped = Some(i);
                }
                if focused && self.moved {
                    r.scroll_to_me(Some(Align::Center));
                }
                ui.add_space(12.0);
            }
        });
        if let Some(i) = tapped {
            let e = self.shell.tap_app(i, self.web);
            self.apply(e);
        }
    }

    /// A module's page: what it is, its paper's abstract, and what it ships.
    fn detail(&mut self, ui: &mut egui::Ui) {
        let Some((a, page)) = self.shell.page().map(|(a, p)| (a.clone(), p)) else {
            self.shell.go_home();
            return;
        };
        ui.add_space(16.0);
        if ui
            .add(
                egui::Label::new(RichText::new("‹ Home").size(15.0).color(MUTED))
                    .sense(Sense::click()),
            )
            .clicked()
        {
            self.shell.go_home();
            return;
        }
        ui.add_space(4.0);
        ui.label(RichText::new(&a.name).size(30.0).color(PAPER).strong());
        ui.label(
            RichText::new(format!("{} · modules/{}", a.category, a.module))
                .size(14.0)
                .color(ACCENT),
        );
        ui.add_space(12.0);
        egui::ScrollArea::vertical().show(ui, |ui| {
            if !a.description.is_empty() {
                ui.label(RichText::new(&a.description).size(17.0).color(PAPER));
                ui.add_space(12.0);
            }
            let card = |ui: &mut egui::Ui, head: &str, body: &str| {
                Frame::new()
                    .fill(CARD)
                    .corner_radius(CornerRadius::same(10))
                    .inner_margin(Margin::same(14))
                    .show(ui, |ui| {
                        ui.set_width(ui.available_width());
                        ui.label(RichText::new(head).size(13.0).color(MUTED).strong());
                        ui.add_space(4.0);
                        ui.label(RichText::new(body).size(15.0).color(PAPER));
                    });
                ui.add_space(8.0);
            };
            if page.title.is_empty() {
                card(
                    ui,
                    "PAPER",
                    "None yet: the module's paper is on the backlog.",
                );
            } else {
                card(ui, "PAPER", &format!("{}\n\n{}", page.title, page.summary));
            }
            for (head, xs) in [
                ("CHECKS", &page.checks),
                ("PACKAGES", &page.packages),
                ("TEAMS", &page.teams),
            ] {
                if !xs.is_empty() {
                    card(ui, head, &xs.join(", "));
                }
            }
        });
    }

    fn sections(&mut self, ui: &mut egui::Ui, wide: bool) {
        let mut tapped = None;
        let titles: Vec<String> = self
            .shell
            .declared
            .sections
            .iter()
            .map(|s| s.title.clone())
            .collect();
        for (i, title) in titles.iter().enumerate() {
            let on = i == self.shell.section;
            let colour = if on && !self.shell.in_rows {
                ACCENT
            } else if on {
                PAPER
            } else {
                MUTED
            };
            let r = if wide {
                let r = ui.add(
                    egui::Label::new(RichText::new(title.as_str()).size(20.0).color(colour))
                        .sense(Sense::click()),
                );
                ui.add_space(10.0);
                r
            } else {
                Frame::new()
                    .fill(if on { RAISED } else { CARD })
                    .corner_radius(CornerRadius::same(18))
                    .inner_margin(Margin::symmetric(14, 8))
                    .show(ui, |ui| {
                        ui.label(RichText::new(title.as_str()).size(16.0).color(colour))
                    })
                    .response
                    .interact(Sense::click())
            };
            if r.clicked() {
                tapped = Some(i);
            }
        }
        if let Some(i) = tapped {
            self.shell.tap_section(i);
        }
    }

    fn rows(&mut self, ui: &mut egui::Ui) {
        let mut tapped = None;
        egui::ScrollArea::vertical().id_salt("rows").show(ui, |ui| {
            let rows = self.shell.rows().to_vec();
            if rows.is_empty() {
                ui.label(RichText::new("Nothing declared here yet.").color(MUTED));
            }
            for (i, e) in rows.iter().enumerate() {
                let on = self.shell.in_rows && i == self.shell.row;
                let r = Frame::new()
                    .fill(if on { RAISED } else { CARD })
                    .corner_radius(CornerRadius::same(10))
                    .inner_margin(Margin::same(14))
                    .stroke(Stroke::new(1.5_f32, if on { ACCENT } else { CARD }))
                    .show(ui, |ui| {
                        ui.set_width(ui.available_width());
                        ui.label(RichText::new(&e.title).size(17.0).color(PAPER));
                        ui.label(RichText::new(&e.detail).size(13.0).color(MUTED));
                    })
                    .response
                    .interact(Sense::click());
                if r.clicked() {
                    tapped = Some(i);
                }
                if on && self.moved {
                    r.scroll_to_me(Some(Align::Center));
                }
                ui.add_space(8.0);
            }
        });
        if let Some(i) = tapped {
            self.shell.tap_row(i);
        }
    }

    fn settings(&mut self, ui: &mut egui::Ui, wide: bool) {
        ui.add_space(16.0);
        if ui
            .add(
                egui::Label::new(RichText::new("‹ Home").size(15.0).color(MUTED))
                    .sense(Sense::click()),
            )
            .clicked()
        {
            self.shell.go_home();
            return;
        }
        ui.add_space(4.0);
        ui.label(RichText::new("Settings").size(30.0).color(PAPER).strong());
        ui.add_space(16.0);
        if wide {
            let h = ui.available_height();
            ui.horizontal_top(|ui| {
                ui.allocate_ui_with_layout(
                    egui::vec2(200.0, h),
                    Layout::top_down(Align::Min),
                    |ui| self.sections(ui, true),
                );
                ui.add_space(24.0);
                let w = ui.available_width();
                ui.allocate_ui_with_layout(egui::vec2(w, h), Layout::top_down(Align::Min), |ui| {
                    self.rows(ui)
                });
            });
        } else {
            ui.horizontal_wrapped(|ui| self.sections(ui, false));
            ui.add_space(16.0);
            self.rows(ui);
        }
    }
}

/// What a card does when it has no description of its own.
fn kind_label(k: &Kind) -> &'static str {
    match k {
        Kind::Native => "a program on this device",
        Kind::Web => "a page behind Access",
        Kind::Builtin => "part of the shell",
        Kind::Module => "a module of the repository",
    }
}

/// In the browser, a web app opens in a tab of its own.
#[cfg(target_arch = "wasm32")]
fn open(url: &str) -> String {
    match web_sys::window().map(|w| w.open_with_url_and_target(url, "_blank")) {
        Some(Ok(_)) => format!("opened {url}"),
        _ => format!("could not open {url}"),
    }
}

#[cfg(not(target_arch = "wasm32"))]
fn open(url: &str) -> String {
    run(&format!("firefox --new-window {url}"))
}

#[cfg(target_arch = "wasm32")]
fn run(cmd: &str) -> String {
    format!("{cmd} runs on a device, not in the browser")
}

/// Under niri, the empty workspace it keeps at the bottom of the stack:
/// a new app opens there, below every app already open.
#[cfg(not(target_arch = "wasm32"))]
fn empty_workspace() -> Option<u64> {
    let out = std::process::Command::new("niri")
        .args(["msg", "--json", "workspaces"])
        .output()
        .ok()?;
    let ws: serde_json::Value = serde_json::from_slice(&out.stdout).ok()?;
    ws.as_array()?
        .iter()
        .filter(|w| w["active_window_id"].is_null())
        .filter_map(|w| w["idx"].as_u64())
        .max()
}

/// Start a program beside the shell, on a workspace of its own.
#[cfg(not(target_arch = "wasm32"))]
fn run(cmd: &str) -> String {
    let mut parts = cmd.split_whitespace();
    let Some(prog) = parts.next() else {
        return String::new();
    };
    if std::env::var_os("NIRI_SOCKET").is_some() {
        if let Some(idx) = empty_workspace() {
            let _ = std::process::Command::new("niri")
                .args(["msg", "action", "focus-workspace", &idx.to_string()])
                .status();
        }
    }
    match std::process::Command::new(prog).args(parts).spawn() {
        Ok(_) => format!("started {prog}"),
        Err(e) => format!("{prog}: {e}"),
    }
}

impl eframe::App for App {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        self.keys(ctx);
        // A phone's width stacks the settings; a wide screen keeps the
        // column to a readable measure, centred.
        let wide = ctx.screen_rect().width() >= 640.0;
        let measure = if self.shell.screen != Screen::Settings {
            760.0
        } else {
            1040.0
        };
        let side: i8 = if wide { 48 } else { 20 };
        egui::CentralPanel::default()
            .frame(
                Frame::new()
                    .fill(INK)
                    .inner_margin(Margin::symmetric(side, 24)),
            )
            .show(ctx, |ui| {
                let avail = ui.available_width();
                let w = avail.min(measure);
                let h = ui.available_height();
                ui.horizontal_top(|ui| {
                    ui.add_space((avail - w) / 2.0);
                    ui.allocate_ui_with_layout(
                        egui::vec2(w, h),
                        Layout::top_down(Align::Min),
                        |ui| {
                            ui.set_width(w);
                            match self.shell.screen {
                                Screen::Home => self.home(ui),
                                Screen::Settings => self.settings(ui, wide),
                                Screen::Detail => self.detail(ui),
                            }
                            if !self.note.is_empty() {
                                ui.add_space(8.0);
                                ui.label(RichText::new(&self.note).size(13.0).color(MUTED));
                            }
                        },
                    );
                });
            });
    }
}

/// The browser's entry: the shell draws on a canvas it makes itself, so
/// the page needs nothing but this module (./page.rs writes it).
#[cfg(target_arch = "wasm32")]
#[wasm_bindgen::prelude::wasm_bindgen(start)]
pub fn start() {
    use wasm_bindgen::JsCast;
    let document = web_sys::window()
        .and_then(|w| w.document())
        .expect("a document");
    let canvas: web_sys::HtmlCanvasElement = document
        .create_element("canvas")
        .expect("a canvas")
        .dyn_into()
        .expect("a canvas element");
    canvas.set_id("kagamizo-shell");
    let style = canvas.style();
    let _ = style.set_property("width", "100vw");
    let _ = style.set_property("height", "100vh");
    let _ = style.set_property("display", "block");
    if let Some(body) = document.body() {
        let _ = body.style().set_property("margin", "0");
        let _ = body.style().set_property("background", "#121418");
        let _ = body.append_child(&canvas);
    }
    wasm_bindgen_futures::spawn_local(async move {
        let _ = eframe::WebRunner::new()
            .start(
                canvas,
                eframe::WebOptions::default(),
                Box::new(|_| Ok(Box::new(App::new("web")))),
            )
            .await;
    });
}
