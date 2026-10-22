//! A flow as Nix declares it (`browser.flows.<provider>.<flow>`), rendered to
//! JSON by the module and checked here again: an unknown field, step, target
//! or value is an error before the browser starts.

use serde::Deserialize;

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Flow {
    /// `provider:flow`, as governance knows it.
    pub action: String,
    /// The held account it runs on.
    pub account: String,
    /// Hosts the browser may be on; a step that finds it anywhere else stops
    /// the flow before anything is typed.
    pub hosts: Vec<String>,
    /// The account's login item, for values read from Proton Pass.
    pub login: Login,
    pub steps: Vec<Step>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Login {
    pub vault: String,
    pub item: String,
    /// The declared address (accounts.held.<a>.login.email).
    pub email: String,
}

#[derive(Debug, Deserialize)]
#[serde(tag = "do", rename_all = "kebab-case", deny_unknown_fields)]
pub enum Step {
    Goto {
        url: String,
    },
    Fill {
        target: Target,
        value: Value,
    },
    Click {
        target: Target,
    },
    WaitFor {
        target: Target,
        seconds: u64,
    },
    WaitUrl {
        prefix: String,
        seconds: u64,
    },
    /// The owner's one manual step: a push, a link, a passkey. The flow
    /// waits until the page shows it went through.
    Approve {
        prompt: String,
        until: Until,
        minutes: u64,
    },
    /// A one-time code the owner reads off their phone, given on stdin.
    Code {
        prompt: String,
        target: Target,
    },
    /// The page's controls and headings by role and name (no values), to
    /// write the next steps against.
    Snapshot,
}

#[derive(Debug, Deserialize)]
#[serde(tag = "by", rename_all = "kebab-case", deny_unknown_fields)]
pub enum Target {
    /// An element by its accessible role and name, as a person sees it.
    Role {
        role: Role,
        name: String,
    },
    Css {
        css: String,
    },
}

/// The ARIA roles a flow may target.
#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Role {
    Button,
    Link,
    Textbox,
    Combobox,
    Checkbox,
    Radio,
    Option,
    Menuitem,
    Tab,
    Heading,
}

impl Role {
    pub fn as_str(self) -> &'static str {
        match self {
            Role::Button => "button",
            Role::Link => "link",
            Role::Textbox => "textbox",
            Role::Combobox => "combobox",
            Role::Checkbox => "checkbox",
            Role::Radio => "radio",
            Role::Option => "option",
            Role::Menuitem => "menuitem",
            Role::Tab => "tab",
            Role::Heading => "heading",
        }
    }
}

#[derive(Debug, Deserialize)]
#[serde(tag = "from", rename_all = "kebab-case", deny_unknown_fields)]
pub enum Value {
    Text {
        text: String,
    },
    /// The account's declared login address.
    Declared,
    /// A field of the account's login item in Proton Pass, never printed.
    Pass {
        field: PassField,
    },
}

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum PassField {
    Username,
    Email,
    Password,
    Totp,
}

#[derive(Debug, Deserialize)]
#[serde(tag = "when", rename_all = "kebab-case", deny_unknown_fields)]
pub enum Until {
    UrlPrefix { prefix: String },
    Shows { target: Target },
}
