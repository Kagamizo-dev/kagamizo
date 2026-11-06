//! agent-spend: what an agent job costs, before it runs, while it runs and
//! after. Prices are OpenRouter's per provider (../prices.json, dated),
//! because OpenRouter routes one model to many providers whose cache-read
//! prices differ by up to 200×: an agent loop re-reads its whole context
//! every step, so the cache-read price is most of the bill.
//!
//!   agent-spend estimate --model M --steps S --context C [--providers P,..]
//!       the job's cost range over the allowed providers, from the shape of
//!       an agent loop: S steps, each re-reading a context that averages C
//!   agent-spend measure  --model M [--providers P,..] LOG.jsonl...
//!       the tokens a finished job's event log records, and their cost
//!   agent-spend run --model M --budget USD [--providers P,..] -- CMD...
//!       run the job, pass its event stream through, and stop it the moment
//!       its cost at the dearest allowed provider reaches the budget
//!
//! Costs are reported at the cheapest and the dearest allowed provider; the
//! budget is held at the dearest, so it holds wherever OpenRouter routes.
use serde::Deserialize;
use std::io::{BufRead, BufReader, Write};
use std::process::{Command, ExitCode, Stdio};

const PRICES: &str = include_str!("../prices.json");

/// One provider's prices, USD per million tokens.
#[derive(Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Endpoint {
    pub provider: String,
    pub input: f64,
    pub cache_read: f64,
    pub output: f64,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Table {
    as_of: String,
    models: std::collections::BTreeMap<String, Vec<Endpoint>>,
}

fn table() -> Table {
    serde_json::from_str(PRICES).expect("prices.json is a valid table")
}

/// Tokens as a job's event log counts them.
#[derive(Default, Clone, Copy, Debug, PartialEq)]
pub struct Usage {
    pub uncached: f64,
    pub cached: f64,
    pub output: f64,
    pub steps: u64,
}

impl Usage {
    pub fn cost(&self, e: &Endpoint) -> f64 {
        (self.uncached * e.input + self.cached * e.cache_read + self.output * e.output) / 1e6
    }

    /// One `{"phase":"step_end","usage":{...}}` event of the harness's stream.
    pub fn add_event(&mut self, line: &str) {
        let Ok(v) = serde_json::from_str::<serde_json::Value>(line) else { return };
        if v["phase"] != "step_end" {
            return;
        }
        let u = &v["usage"];
        let n = |k: &str| u[k].as_f64().unwrap_or(0.0);
        self.uncached += n("inputTokens");
        self.cached += n("cacheReadTokens");
        self.output += n("outputTokens");
        self.steps += 1;
    }
}

/// The endpoints a job may be routed to: the model's, narrowed to the
/// allowed providers when they are named.
pub fn allowed(model: &str, providers: Option<&[String]>) -> Result<Vec<Endpoint>, String> {
    let t = table();
    let eps = t.models.get(model).ok_or_else(|| {
        format!("no prices for {model} (prices.json, {}); priced: {}", t.as_of, t.models.keys().cloned().collect::<Vec<_>>().join(", "))
    })?;
    let out: Vec<Endpoint> = match providers {
        None => eps.clone(),
        // Exact endpoint tags (provider/quantization): a provider's
        // priority tier is another endpoint at another price.
        Some(ps) => eps.iter().filter(|e| ps.iter().any(|p| e.provider == *p)).cloned().collect(),
    };
    if out.is_empty() {
        return Err(format!("none of {model}'s providers is allowed"));
    }
    Ok(out)
}

/// (cheapest, dearest) cost of the usage over the endpoints.
pub fn range(u: &Usage, eps: &[Endpoint]) -> (f64, f64) {
    let costs: Vec<f64> = eps.iter().map(|e| u.cost(e)).collect();
    (costs.iter().cloned().fold(f64::INFINITY, f64::min), costs.iter().cloned().fold(0.0, f64::max))
}

/// An agent loop of `steps` steps re-reading a context averaging `context`
/// tokens: the share of each step's input that is new (not a cache read) and
/// the output per step are the medians measured over the teams' jobs of
/// 2026-11-05 and -06 (1,814 steps: 1.4% new input, 335 output tokens).
pub const NEW_INPUT_SHARE: f64 = 0.014;
pub const OUTPUT_PER_STEP: f64 = 335.0;

pub fn shape(steps: u64, context: f64) -> Usage {
    let input = steps as f64 * context;
    Usage {
        uncached: input * NEW_INPUT_SHARE,
        cached: input * (1.0 - NEW_INPUT_SHARE),
        output: steps as f64 * OUTPUT_PER_STEP,
        steps,
    }
}

fn usd(x: f64) -> String {
    format!("${x:.4}")
}

struct Args {
    model: Option<String>,
    providers: Option<Vec<String>>,
    steps: Option<u64>,
    context: Option<f64>,
    budget: Option<f64>,
    rest: Vec<String>,
}

fn parse(args: &[String]) -> Result<Args, String> {
    let mut a = Args { model: None, providers: None, steps: None, context: None, budget: None, rest: vec![] };
    let mut it = args.iter();
    while let Some(x) = it.next() {
        let mut val = || it.next().cloned().ok_or_else(|| format!("{x} needs a value"));
        match x.as_str() {
            "--model" => a.model = Some(val()?),
            "--providers" => a.providers = Some(val()?.split(',').map(str::to_string).collect()),
            "--steps" => a.steps = Some(val()?.parse().map_err(|e| format!("--steps: {e}"))?),
            "--context" => a.context = Some(val()?.parse().map_err(|e| format!("--context: {e}"))?),
            "--budget" => a.budget = Some(val()?.parse().map_err(|e| format!("--budget: {e}"))?),
            "--" => {
                a.rest = it.cloned().collect();
                break;
            }
            _ => a.rest.push(x.clone()),
        }
    }
    Ok(a)
}

fn report(what: &str, u: &Usage, eps: &[Endpoint]) {
    let (lo, hi) = range(u, eps);
    let cheapest = eps.iter().min_by(|a, b| u.cost(a).partial_cmp(&u.cost(b)).unwrap()).unwrap();
    let dearest = eps.iter().max_by(|a, b| u.cost(a).partial_cmp(&u.cost(b)).unwrap()).unwrap();
    println!(
        "{what}: {} steps, {:.1}M new input, {:.1}M cache reads, {:.2}M output; {} at {} .. {} at {}",
        u.steps, u.uncached / 1e6, u.cached / 1e6, u.output / 1e6, usd(lo), cheapest.provider, usd(hi), dearest.provider
    );
}

/// Run the job under the budget; Ok(cost) or the job's own failure.
fn run(cmd: &[String], budget: f64, eps: &[Endpoint]) -> Result<(f64, bool), String> {
    let (prog, args) = cmd.split_first().ok_or("run needs -- CMD")?;
    let mut child = Command::new(prog).args(args).stdout(Stdio::piped()).spawn().map_err(|e| format!("{prog}: {e}"))?;
    let out = child.stdout.take().expect("piped stdout");
    let mut u = Usage::default();
    let mut stdout = std::io::stdout();
    let mut stopped = false;
    for line in BufReader::new(out).lines() {
        let Ok(line) = line else { break };
        let _ = writeln!(stdout, "{line}");
        u.add_event(&line);
        let (_, hi) = range(&u, eps);
        if hi >= budget {
            eprintln!("agent-spend: {} after {} steps reaches the budget {}; stopping the job", usd(hi), u.steps, usd(budget));
            let _ = child.kill();
            stopped = true;
            break;
        }
    }
    let status = child.wait().map_err(|e| e.to_string())?;
    let (lo, hi) = range(&u, eps);
    eprintln!("agent-spend: {} steps, {} .. {} (budget {})", u.steps, usd(lo), usd(hi), usd(budget));
    Ok((hi, stopped || !status.success()))
}

fn main() -> ExitCode {
    let argv: Vec<String> = std::env::args().skip(1).collect();
    let Some((cmd, rest)) = argv.split_first() else {
        eprintln!("usage: agent-spend estimate|measure|run --model M ...");
        return ExitCode::from(2);
    };
    let go = || -> Result<ExitCode, String> {
        let a = parse(rest)?;
        let model = a.model.as_deref().ok_or("--model is required")?;
        let eps = allowed(model, a.providers.as_deref())?;
        match cmd.as_str() {
            "estimate" => {
                let u = shape(a.steps.ok_or("--steps is required")?, a.context.ok_or("--context is required")?);
                report(&format!("estimate ({model})"), &u, &eps);
                Ok(ExitCode::SUCCESS)
            }
            "measure" => {
                let mut total = Usage::default();
                for path in &a.rest {
                    let mut u = Usage::default();
                    for line in std::fs::read_to_string(path).map_err(|e| format!("{path}: {e}"))?.lines() {
                        u.add_event(line);
                    }
                    report(path, &u, &eps);
                    total.uncached += u.uncached;
                    total.cached += u.cached;
                    total.output += u.output;
                    total.steps += u.steps;
                }
                report(&format!("total ({model})"), &total, &eps);
                Ok(ExitCode::SUCCESS)
            }
            "run" => {
                let budget = a.budget.ok_or("--budget is required")?;
                let (_, failed) = run(&a.rest, budget, &eps)?;
                Ok(if failed { ExitCode::FAILURE } else { ExitCode::SUCCESS })
            }
            other => Err(format!("no command {other}")),
        }
    };
    match go() {
        Ok(c) => c,
        Err(e) => {
            eprintln!("agent-spend: {e}");
            ExitCode::from(2)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ep(provider: &str, input: f64, cache_read: f64, output: f64) -> Endpoint {
        Endpoint { provider: provider.into(), input, cache_read, output }
    }

    #[test]
    fn cost_is_per_million_by_kind() {
        let u = Usage { uncached: 1e6, cached: 10e6, output: 1e6, steps: 1 };
        assert!((u.cost(&ep("x", 0.1, 0.01, 0.2)) - 0.4).abs() < 1e-12);
    }

    #[test]
    fn step_events_are_counted() {
        let mut u = Usage::default();
        u.add_event(r#"{"type":"status","phase":"step_end","usage":{"inputTokens":2001,"outputTokens":279,"cacheReadTokens":7936}}"#);
        u.add_event(r#"{"type":"status","phase":"turn_end"}"#);
        u.add_event("not json");
        assert_eq!(u, Usage { uncached: 2001.0, cached: 7936.0, output: 279.0, steps: 1 });
    }

    #[test]
    fn the_providers_narrow_the_range() {
        let all = allowed("deepseek/deepseek-v4-flash", None).unwrap();
        let cheap = allowed("deepseek/deepseek-v4-flash", Some(&["deepinfra/fp8".to_string()])).unwrap();
        let u = shape(400, 200_000.0);
        assert!(range(&u, &cheap).1 < range(&u, &all).1);
        assert!(allowed("deepseek/deepseek-v4-flash", Some(&["nowhere".to_string()])).is_err());
    }

    #[test]
    fn the_cheap_route_is_far_cheaper_than_the_billed_one() {
        // 2026-11-05's billed shape: 146.8M prompt tokens, 97% cache reads.
        let u = Usage { uncached: 3.9e6, cached: 142.9e6, output: 0.88e6, steps: 0 };
        let parasail = allowed("deepseek/deepseek-v4-flash", Some(&["parasail/fp8".to_string()])).unwrap();
        let baidu = allowed("deepseek/deepseek-v4.1-flash", Some(&["baidu/fp8".to_string()])).unwrap();
        let (_, billed) = range(&u, &parasail);
        let (_, cheap) = range(&u, &baidu);
        assert!(billed > 10.0 && billed < 12.0, "{billed}");
        assert!(cheap < 0.6, "{cheap}");
    }

    #[test]
    fn run_stops_a_job_at_its_budget() {
        // A stand-in job that reports steps of 1M cache reads, forever.
        let script = r#"while true; do echo '{"phase":"step_end","usage":{"inputTokens":0,"outputTokens":0,"cacheReadTokens":1000000}}'; done"#;
        let eps = vec![ep("x", 0.1, 0.01, 0.2)];
        let (spent, stopped) = run(&["sh".into(), "-c".into(), script.into()], 0.05, &eps).unwrap();
        assert!(stopped);
        assert!(spent >= 0.05 && spent < 0.06, "{spent}");
    }
}
