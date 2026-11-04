//! `api-check MODEL.json WORDS...`: whether a command line is one the pinned
//! tool accepts, by the model ../_lean/Api.lean states and
//! ../_render/catalog.py writes (the same model, as JSON).
//!
//! Exit 0 when accepted; 2, with the reason, when not. Nothing is run.

use serde::Deserialize;
use std::collections::BTreeMap;
use std::process::ExitCode;

#[derive(Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
enum Ty {
    #[serde(rename = "string")]
    Str,
    Bool,
    Flag,
    Int,
    Number,
    Duration,
    Ip,
    Cidr,
    Json,
    Pairs,
    List(Box<Ty>),
    OneOf(Vec<String>),
    Named(String),
}

#[derive(Deserialize, Debug)]
struct Input {
    name: String,
    ty: Ty,
    required: bool,
    #[serde(default)]
    positional: bool,
}

#[derive(Deserialize, Debug)]
struct Operation {
    name: String,
    inputs: Vec<Input>,
}

#[derive(Deserialize, Debug)]
struct Api {
    name: String,
    ops: Vec<Operation>,
}

/// Whether a value given on the command line fits a type (`Value.fits`,
/// for the string a command line carries).
fn fits(v: &str, t: &Ty) -> bool {
    match t {
        Ty::Str | Ty::Duration | Ty::Ip | Ty::Cidr | Ty::Pairs | Ty::Named(_) | Ty::Json => true,
        Ty::Bool => v == "true" || v == "false",
        Ty::Flag => false,
        Ty::Int => v.parse::<i64>().is_ok(),
        Ty::Number => v.parse::<f64>().is_ok(),
        Ty::OneOf(vs) => vs.iter().any(|x| x == v),
        Ty::List(inner) => fits(v, inner),
    }
}

fn is_flag(t: &Ty) -> bool {
    matches!(t, Ty::Flag)
}

fn takes_many(t: &Ty) -> bool {
    matches!(t, Ty::List(_))
}

/// Checks one command line against the API; Err is the reason it is refused.
fn check(api: &Api, args: &[String]) -> Result<String, String> {
    // Which option names are flags anywhere: an option before the command
    // words (a global one) is read before the command is known.
    let mut flags: BTreeMap<&str, bool> = BTreeMap::new();
    for o in &api.ops {
        for i in o.inputs.iter().filter(|i| !i.positional) {
            let f = flags.entry(&i.name).or_insert(true);
            *f = *f && is_flag(&i.ty);
        }
    }
    // Split into words and options, by name.
    let mut words: Vec<&str> = Vec::new();
    let mut opts: Vec<(String, Option<String>)> = Vec::new();
    let mut k = 0;
    while k < args.len() {
        let a = &args[k];
        if a == "--" {
            words.extend(args[k + 1..].iter().map(String::as_str));
            break;
        }
        if let Some(rest) = a.strip_prefix("--") {
            if let Some((n, v)) = rest.split_once('=') {
                opts.push((n.to_string(), Some(v.to_string())));
            } else {
                let base = rest.strip_prefix("no-").filter(|b| flags.get(b) == Some(&true));
                let n = base.unwrap_or(rest);
                if !flags.contains_key(n) {
                    return Err(format!("{}: no command takes an option --{n}", api.name));
                }
                if flags.get(n).copied().unwrap_or(false) || base.is_some() {
                    opts.push((n.to_string(), None));
                } else {
                    let v = args.get(k + 1).ok_or(format!("--{rest} needs a value"))?;
                    opts.push((rest.to_string(), Some(v.clone())));
                    k += 1;
                }
            }
        } else if a.starts_with('-') && a.len() > 1 && a.parse::<f64>().is_err() {
            return Err(format!("{a}: short options are not in the model; use the long name"));
        } else {
            words.push(a);
        }
        k += 1;
    }
    // The command: the longest run of leading words that names an operation.
    let (op, used) = (1..=words.len())
        .rev()
        .find_map(|n| {
            let name = words[..n].join(" ");
            api.ops.iter().find(|o| o.name == name).map(|o| (o, n))
        })
        .ok_or_else(|| {
            format!("{}: no command `{}` in the pinned catalog", api.name, words.join(" "))
        })?;
    let input = |n: &str| op.inputs.iter().find(|i| !i.positional && i.name == n);
    let mut given: BTreeMap<String, usize> = BTreeMap::new();
    for (n, v) in &opts {
        if n == "help" {
            continue;
        }
        let i = input(n).ok_or(format!("{}: `{}` takes no option --{n}", api.name, op.name))?;
        match (v, is_flag(&i.ty)) {
            (None, true) => {}
            (Some(v), true) if v == "true" || v == "false" => {}
            (None, false) => return Err(format!("--{n} needs a value")),
            (Some(v), _) if !fits(v, &i.ty) => {
                return Err(format!("--{n} {v:?} is not a value of {:?}", i.ty))
            }
            _ => {}
        }
        let c = given.entry(n.clone()).or_default();
        *c += 1;
        if *c > 1 && !takes_many(&i.ty) {
            return Err(format!("--{n} is given more than once"));
        }
    }
    // Positional arguments, in order; a list takes the rest.
    let mut rest = words[used..].iter();
    for i in op.inputs.iter().filter(|i| i.positional) {
        if takes_many(&i.ty) {
            let vs: Vec<_> = rest.by_ref().collect();
            if let Some(v) = vs.iter().find(|v| !fits(v, &i.ty)) {
                return Err(format!("{} {v:?} is not a value of {:?}", i.name, i.ty));
            }
            if !vs.is_empty() {
                given.insert(i.name.clone(), vs.len());
            }
        } else if let Some(v) = rest.next() {
            if !fits(v, &i.ty) {
                return Err(format!("{} {v:?} is not a value of {:?}", i.name, i.ty));
            }
            given.insert(i.name.clone(), 1);
        }
    }
    if let Some(extra) = rest.next() {
        return Err(format!("`{}` takes no further argument {extra:?}", op.name));
    }
    if let Some(i) = op.inputs.iter().find(|i| i.required && !given.contains_key(&i.name)) {
        return Err(format!("`{}` requires {}", op.name, i.name));
    }
    Ok(op.name.clone())
}

fn main() -> ExitCode {
    let mut argv = std::env::args().skip(1);
    let Some(model) = argv.next() else {
        eprintln!("usage: api-check MODEL.json WORDS...");
        return ExitCode::from(2);
    };
    let api: Api = match std::fs::read(&model).map_err(|e| e.to_string()).and_then(|b| {
        serde_json::from_slice(&b).map_err(|e| e.to_string())
    }) {
        Ok(a) => a,
        Err(e) => {
            eprintln!("api-check: {model}: {e}");
            return ExitCode::from(2);
        }
    };
    let args: Vec<String> = argv.collect();
    match check(&api, &args) {
        Ok(_) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("api-check: refused: {e}");
            ExitCode::from(2)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn public() -> Api {
        let path = std::env::var("API_CHECK_PUBLIC").expect("API_CHECK_PUBLIC: Public's model");
        serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap()
    }

    fn run(args: &[&str]) -> Result<String, String> {
        check(&public(), &args.iter().map(|s| s.to_string()).collect::<Vec<_>>())
    }

    // The same calls ../../public/_lean/Calls.lean proves about.
    #[test]
    fn summary_accepted() {
        assert_eq!(run(&["accounts", "list"]).unwrap(), "accounts list");
        assert_eq!(run(&["--json", "portfolio", "show"]).unwrap(), "portfolio show");
    }

    #[test]
    fn bars_accepted() {
        assert!(run(&["historicdata", "bars", "EQUITY", "SPY", "YEAR"]).is_ok());
    }

    #[test]
    fn unknown_refused() {
        assert!(run(&["accounts", "drain"]).is_err());
    }

    #[test]
    fn unknown_option_refused() {
        assert!(run(&["accounts", "list", "--withdraw"]).is_err());
    }

    #[test]
    fn order_needs_file() {
        assert!(run(&["order", "place"]).is_err());
        assert!(run(&["order", "place", "--file", "o.json"]).is_ok());
    }

    #[test]
    fn wrong_type_refused() {
        assert!(run(&["--timeout", "soon", "accounts", "list"]).is_err());
        assert!(run(&["--timeout", "30", "accounts", "list"]).is_ok());
    }

    #[test]
    fn missing_argument_refused() {
        assert!(run(&["historicdata", "bars", "EQUITY", "SPY"]).is_err());
        assert!(run(&["historicdata", "bars", "EQUITY", "SPY", "YEAR", "extra"]).is_err());
    }
}
