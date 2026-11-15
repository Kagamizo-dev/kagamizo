//! The shell as plain pages: documents as values (./html.rs), one stylesheet
//! from typed tokens (./style.rs), the audit every page passes before it is
//! written (./a11y.rs) and the pages themselves (./pages.rs). The chat
//! gateway (../../agents/_chat) builds its pages from the same parts, so a
//! page it renders reads and looks like the rest.
#[path = "../../_shell/src/model.rs"]
#[allow(dead_code)]
pub mod model;

pub mod a11y;
pub mod html;
pub mod pages;
pub mod style;
