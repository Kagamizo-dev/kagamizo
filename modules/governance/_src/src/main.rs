//! `cedar-tests`: the governance tests (modules/governance/cedar.nix) run
//! in-process on the pinned cedar-policy crate (the same version as the
//! cedar CLI), the entities parsed and validated against the schema once
//! and every request authorized against them. `cedar run-tests` takes the
//! entities inside each test and validates them again per test: 6289 tests
//! × 12 KB of entities was 70 MB of JSON and two minutes; this is seconds.
//!
//!   cedar-tests --schema S --policies P --entities E --tests T
//!
//! T is `cedar run-tests`' own format less the per-test `entities`:
//! name, request (principal, action, resource, context), decision, reason
//! (the policy ids expected to decide it) and num_errors.

use std::collections::BTreeSet;
use std::fs;
use std::str::FromStr;

use anyhow::{bail, Context, Result};
use cedar_policy::{Authorizer, Decision, Entities, EntityUid, PolicyId, PolicySet, Request, Schema};
use serde::Deserialize;
use serde_json::Value;

#[derive(Deserialize)]
struct Test {
    name: Option<String>,
    request: Req,
    decision: String,
    #[serde(default)]
    reason: Vec<String>,
    #[serde(default)]
    num_errors: usize,
}

#[derive(Deserialize)]
struct Req {
    principal: String,
    action: String,
    resource: String,
    #[serde(default)]
    context: Value,
}

fn arg(args: &[String], name: &str) -> Result<String> {
    args.iter()
        .position(|a| a == name)
        .and_then(|i| args.get(i + 1))
        .cloned()
        .with_context(|| format!("usage: cedar-tests --schema S --policies P --entities E --tests T (missing {name})"))
}

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let schema_text = fs::read_to_string(arg(&args, "--schema")?)?;
    let (schema, warnings) = Schema::from_cedarschema_str(&schema_text).context("schema")?;
    for w in warnings {
        eprintln!("schema: {w}");
    }
    let parsed = PolicySet::from_str(&fs::read_to_string(arg(&args, "--policies")?)?).context("policies")?;
    // The CLI names each policy by its `@id("...")` annotation; the crate
    // numbers them, so the names are applied here for the reasons to match.
    let mut policies = PolicySet::new();
    for p in parsed.policies() {
        let named = match p.annotation("id") {
            Some(id) => p.new_id(PolicyId::new(id)),
            None => p.clone(),
        };
        policies.add(named).context("policy ids")?;
    }
    for t in parsed.templates() {
        let named = match t.annotation("id") {
            Some(id) => t.new_id(PolicyId::new(id)),
            None => t.clone(),
        };
        policies.add_template(named).context("template ids")?;
    }
    let entities = Entities::from_json_str(&fs::read_to_string(arg(&args, "--entities")?)?, Some(&schema)).context("entities")?;
    let tests: Vec<Test> = serde_json::from_str(&fs::read_to_string(arg(&args, "--tests")?)?).context("tests")?;

    let authorizer = Authorizer::new();
    let mut failed = 0usize;
    for (i, t) in tests.iter().enumerate() {
        let name = t.name.clone().unwrap_or_else(|| format!("test {i}"));
        let principal = EntityUid::from_str(&t.request.principal).with_context(|| format!("{name}: principal"))?;
        let action = EntityUid::from_str(&t.request.action).with_context(|| format!("{name}: action"))?;
        let resource = EntityUid::from_str(&t.request.resource).with_context(|| format!("{name}: resource"))?;
        let context = cedar_policy::Context::from_json_value(t.request.context.clone(), Some((&schema, &action)))
            .with_context(|| format!("{name}: context"))?;
        let request = Request::new(principal, action, resource, context, Some(&schema)).with_context(|| format!("{name}: request"))?;
        let response = authorizer.is_authorized(&request, &policies, &entities);
        let decision = match response.decision() {
            Decision::Allow => "allow",
            Decision::Deny => "deny",
        };
        let reasons: BTreeSet<String> = response.diagnostics().reason().map(|p| p.to_string()).collect();
        let expected: BTreeSet<String> = t.reason.iter().cloned().collect();
        let errors = response.diagnostics().errors().count();
        let mut problems = Vec::new();
        if decision != t.decision {
            problems.push(format!("decision {decision}, expected {}", t.decision));
        }
        if reasons != expected {
            problems.push(format!("reason {:?}, expected {:?}", reasons, expected));
        }
        if errors != t.num_errors {
            problems.push(format!("{errors} erroring policies, expected {}", t.num_errors));
        }
        if problems.is_empty() {
            continue;
        }
        failed += 1;
        println!("  test {name} ... FAILED: {}", problems.join("; "));
    }
    println!("results: {} passed, {failed} failed", tests.len() - failed);
    if failed > 0 {
        bail!("{failed} governance test(s) failed");
    }
    Ok(())
}
