//! Who Cloudflare Access vouches for. Every request that reaches this
//! gateway through the tunnel carries an assertion Access signed
//! (`Cf-Access-Jwt-Assertion`). It is believed only if one of the team's
//! published keys signed it, the team issued it and it has not expired;
//! then the address in it is who is asking. A service token's assertion
//! names no address, so it speaks for no one here.
use jsonwebtoken::{decode, decode_header, Algorithm, DecodingKey, Validation};
use serde_json::Value;
use std::time::{Duration, Instant};

pub struct Access {
    /// The team's own host, as `name.cloudflareaccess.com`.
    team: String,
    keys: Vec<Value>,
    fetched: Option<Instant>,
}

impl Access {
    pub fn new(team: &str) -> Self {
        Access { team: team.to_owned(), keys: Vec::new(), fetched: None }
    }

    fn refresh(&mut self) {
        // At most once a minute, so a stream of bad assertions asks nothing.
        if self.fetched.is_some_and(|t| t.elapsed() < Duration::from_secs(60)) {
            return;
        }
        self.fetched = Some(Instant::now());
        let got = ureq::get(&format!("https://{}/cdn-cgi/access/certs", self.team)).timeout(Duration::from_secs(10)).call();
        if let Ok(body) = got.and_then(|r| r.into_json::<Value>().map_err(Into::into)) {
            if let Some(keys) = body["keys"].as_array() {
                self.keys = keys.clone();
            }
        }
    }

    fn key(&self, kid: &str) -> Option<DecodingKey> {
        let k = self.keys.iter().find(|k| k["kid"] == kid)?;
        DecodingKey::from_rsa_components(k["n"].as_str()?, k["e"].as_str()?).ok()
    }

    /// The address the assertion vouches for, if it is to be believed.
    pub fn who(&mut self, assertion: &str) -> Option<String> {
        let kid = decode_header(assertion).ok()?.kid?;
        if self.key(&kid).is_none() {
            self.refresh();
        }
        let key = self.key(&kid)?;
        let mut rules = Validation::new(Algorithm::RS256);
        rules.set_issuer(&[format!("https://{}", self.team)]);
        // The audience differs per application; the team, the signature,
        // the expiry and the owner's address are what is held to.
        rules.validate_aud = false;
        let claims = decode::<Value>(assertion, &key, &rules).ok()?.claims;
        claims["email"].as_str().filter(|e| !e.is_empty()).map(str::to_owned)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn what_no_key_of_the_team_signed_vouches_for_no_one() {
        let mut access = Access::new("example.invalid");
        access.fetched = Some(Instant::now());
        // A well-formed assertion signed by nobody we know.
        let forged = "eyJhbGciOiJSUzI1NiIsImtpZCI6Im5vbmUifQ.eyJlbWFpbCI6Im93bmVyQGV4YW1wbGUub3JnIiwiaXNzIjoiaHR0cHM6Ly9leGFtcGxlLmludmFsaWQifQ.AAAA";
        assert_eq!(access.who(forged), None);
        assert_eq!(access.who("not an assertion"), None);
        assert_eq!(access.who(""), None);
    }

    #[test]
    fn an_unsigned_assertion_is_not_believed() {
        let mut access = Access::new("example.invalid");
        access.fetched = Some(Instant::now());
        // alg none, no kid.
        assert_eq!(access.who("eyJhbGciOiJub25lIn0.eyJlbWFpbCI6Im93bmVyQGV4YW1wbGUub3JnIn0."), None);
    }
}
