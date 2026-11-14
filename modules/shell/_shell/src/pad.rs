//! Gamepads, mapped onto the model's keys: the d-pad or left stick moves,
//! the south button (A) opens, the east button (B) goes back. Natively
//! through gilrs (evdev, via udev); in the browser through the Gamepad API's
//! standard mapping. A key counts once, when it is first pressed.
use crate::model::Key;

/// Which keys the pads hold now, from the standard mapping's buttons and
/// the left stick.
#[cfg_attr(not(target_arch = "wasm32"), allow(dead_code))]
fn held(buttons: &[bool], axes: &[f64]) -> Vec<Key> {
    let b = |i: usize| buttons.get(i).copied().unwrap_or(false);
    let a = |i: usize| axes.get(i).copied().unwrap_or(0.0);
    let mut keys = Vec::new();
    for (on, k) in [
        (b(12) || a(1) < -0.5, Key::Up),
        (b(13) || a(1) > 0.5, Key::Down),
        (b(14) || a(0) < -0.5, Key::Left),
        (b(15) || a(0) > 0.5, Key::Right),
        (b(0), Key::Enter),
        (b(1), Key::Back),
    ] {
        if on {
            keys.push(k);
        }
    }
    keys
}

pub struct Pads {
    prev: Vec<Key>,
    #[cfg(not(target_arch = "wasm32"))]
    gilrs: Option<gilrs::Gilrs>,
}

impl Pads {
    pub fn new() -> Pads {
        Pads {
            prev: Vec::new(),
            #[cfg(not(target_arch = "wasm32"))]
            gilrs: gilrs::Gilrs::new().ok(),
        }
    }

    /// The keys newly pressed since the last frame.
    pub fn poll(&mut self) -> Vec<Key> {
        let now = self.now();
        let fresh = now
            .iter()
            .copied()
            .filter(|k| !self.prev.contains(k))
            .collect();
        self.prev = now;
        fresh
    }

    #[cfg(target_arch = "wasm32")]
    fn now(&mut self) -> Vec<Key> {
        use wasm_bindgen::JsCast;
        let Some(pads) = web_sys::window().and_then(|w| w.navigator().get_gamepads().ok()) else {
            return Vec::new();
        };
        let mut keys = Vec::new();
        for p in pads.iter() {
            let Ok(pad) = p.dyn_into::<web_sys::Gamepad>() else {
                continue;
            };
            let buttons: Vec<bool> = pad
                .buttons()
                .iter()
                .map(|b| {
                    b.dyn_into::<web_sys::GamepadButton>()
                        .map(|b| b.pressed())
                        .unwrap_or(false)
                })
                .collect();
            let axes: Vec<f64> = pad
                .axes()
                .iter()
                .map(|a| a.as_f64().unwrap_or(0.0))
                .collect();
            for k in held(&buttons, &axes) {
                if !keys.contains(&k) {
                    keys.push(k);
                }
            }
        }
        keys
    }

    #[cfg(not(target_arch = "wasm32"))]
    fn now(&mut self) -> Vec<Key> {
        use gilrs::{Axis, Button};
        let Some(g) = self.gilrs.as_mut() else {
            return Vec::new();
        };
        while g.next_event().is_some() {}
        let mut keys = Vec::new();
        for (_, pad) in g.gamepads() {
            let b = |x| pad.is_pressed(x);
            let a = |x| pad.value(x) as f64;
            for (on, k) in [
                (b(Button::DPadUp) || a(Axis::LeftStickY) > 0.5, Key::Up),
                (b(Button::DPadDown) || a(Axis::LeftStickY) < -0.5, Key::Down),
                (b(Button::DPadLeft) || a(Axis::LeftStickX) < -0.5, Key::Left),
                (
                    b(Button::DPadRight) || a(Axis::LeftStickX) > 0.5,
                    Key::Right,
                ),
                (b(Button::South), Key::Enter),
                (b(Button::East), Key::Back),
            ] {
                if on && !keys.contains(&k) {
                    keys.push(k);
                }
            }
        }
        keys
    }
}

impl Default for Pads {
    fn default() -> Self {
        Pads::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_standard_mapping_gives_the_keys() {
        let mut buttons = vec![false; 16];
        buttons[0] = true;
        buttons[13] = true;
        assert_eq!(held(&buttons, &[0.0, 0.0]), vec![Key::Down, Key::Enter]);
        assert_eq!(held(&[], &[-0.9, 0.0]), vec![Key::Left]);
        assert_eq!(held(&[], &[0.2, -0.2]), Vec::<Key>::new());
    }
}
