//! A passkey Proton Pass saved into a login item, as the engine's virtual
//! authenticator takes it. The item's `passkeys[].content` is Proton's own
//! format (proton-pass-common, src/passkey/passkey_handling.rs and
//! protonpasskey.rs): MessagePack `{c: bytes, v: 1}` around a MessagePack
//! `ProtonPassKey`, whose key is a COSE key with its parameters as
//! (label, value) pairs. An ES256 key (EC2, P-256: crv 1, x -2, y -3,
//! d -4) becomes the PKCS#8 private key the DevTools Protocol's
//! WebAuthn.Credential takes. Nothing here is printed; the private key
//! lives only in memory, zeroed on drop.

use anyhow::{bail, Context, Result};
use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use p256::elliptic_curve::sec1::ToEncodedPoint;
use p256::pkcs8::EncodePrivateKey;
use serde::Deserialize;
use serde_bytes::ByteBuf;
use serde_json::{json, Value};
use zeroize::Zeroizing;

#[derive(Deserialize)]
struct Serialized {
    #[serde(rename = "c")]
    content: ByteBuf,
    #[serde(rename = "v")]
    version: u8,
}

#[derive(Deserialize)]
struct ProtonPassKey {
    key: ProtonKey,
    #[serde(rename = "cid")]
    credential_id: ByteBuf,
    #[serde(rename = "rid")]
    rp_id: String,
    #[serde(rename = "uhd")]
    user_handle: Option<ByteBuf>,
    #[serde(rename = "cnt")]
    counter: Option<u32>,
}

#[derive(Deserialize)]
struct ProtonKey {
    #[serde(rename = "par")]
    params: Vec<(Label, CoseValue)>,
}

#[derive(Deserialize, PartialEq)]
#[serde(tag = "t", content = "c")]
enum Label {
    #[serde(rename = "int")]
    Int(i64),
    #[serde(rename = "txt")]
    Text(String),
}

#[derive(Deserialize)]
struct ProtonInteger {
    /// Little-endian two's complement, up to 16 bytes.
    inner: ByteBuf,
}

#[derive(Deserialize)]
#[serde(tag = "t", content = "c")]
#[allow(dead_code)] // every variant Proton writes must deserialize
enum CoseValue {
    #[serde(rename = "int")]
    Integer(ProtonInteger),
    #[serde(rename = "bytes")]
    Bytes(ByteBuf),
    #[serde(rename = "float")]
    Float(f64),
    #[serde(rename = "txt")]
    Text(String),
    #[serde(rename = "bool")]
    Bool(bool),
    #[serde(rename = "null")]
    Null,
    #[serde(rename = "tag")]
    Tag(u64, Box<CoseValue>),
    #[serde(rename = "array")]
    Array(Vec<CoseValue>),
    #[serde(rename = "map")]
    Map(Vec<(CoseValue, CoseValue)>),
}

impl ProtonInteger {
    fn value(&self) -> i128 {
        let mut bytes = [0u8; 16];
        for (i, b) in self.inner.iter().take(16).enumerate() {
            bytes[i] = *b;
        }
        i128::from_le_bytes(bytes)
    }
}

impl ProtonKey {
    fn param(&self, label: i64) -> Option<&CoseValue> {
        self.params
            .iter()
            .find(|(l, _)| *l == Label::Int(label))
            .map(|(_, v)| v)
    }

    fn bytes(&self, label: i64) -> Result<&[u8]> {
        match self.param(label) {
            Some(CoseValue::Bytes(b)) => Ok(b),
            _ => bail!("the passkey's COSE key has no bytes at {label}"),
        }
    }
}

/// One `passkeys[].content` as a WebAuthn.Credential for its rpId.
pub fn credential(content: &[u8]) -> Result<(String, Value)> {
    let outer: Serialized = rmp_serde::from_slice(content).context("not Proton's passkey format")?;
    if outer.version != 1 {
        bail!("Proton passkey format version {} is not mapped", outer.version);
    }
    let key: ProtonPassKey =
        rmp_serde::from_slice(&outer.content).context("not a ProtonPassKey")?;
    // ES256 on P-256 only: kty is held by the curve and the key's own check.
    match key.key.param(-1) {
        Some(CoseValue::Integer(i)) if i.value() == 1 => {}
        _ => bail!("the passkey is not on P-256 (COSE crv 1)"),
    }
    let d = Zeroizing::new(key.key.bytes(-4)?.to_vec());
    let secret = p256::SecretKey::from_slice(&d).context("the passkey's private key")?;
    // Its public half must be the one stored beside it.
    let point = secret.public_key().to_encoded_point(false);
    if point.x().map(|x| x.as_slice()) != Some(key.key.bytes(-2)?)
        || point.y().map(|y| y.as_slice()) != Some(key.key.bytes(-3)?)
    {
        bail!("the passkey's public key does not match its private key");
    }
    let der = secret.to_pkcs8_der().context("the passkey as PKCS#8")?;
    let mut credential = json!({
        "credentialId": STANDARD.encode(&key.credential_id),
        "isResidentCredential": true,
        "rpId": key.rp_id,
        "privateKey": STANDARD.encode(der.as_bytes()),
        "signCount": key.counter.unwrap_or(0),
    });
    if let Some(handle) = &key.user_handle {
        credential["userHandle"] = json!(STANDARD.encode(handle));
    }
    Ok((key.rp_id, credential))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::Serialize;

    #[derive(Serialize)]
    struct Pk<'a> {
        key: Key<'a>,
        cid: ByteBuf,
        rid: &'a str,
        uhd: Option<ByteBuf>,
        cnt: Option<u32>,
    }
    #[derive(Serialize)]
    struct Key<'a> {
        kty: serde_json::Value,
        kid: ByteBuf,
        alg: Option<serde_json::Value>,
        kops: Vec<u8>,
        biv: ByteBuf,
        par: Vec<(serde_json::Value, serde_json::Value)>,
        #[serde(skip)]
        _p: std::marker::PhantomData<&'a ()>,
    }
    #[derive(Serialize)]
    struct Outer {
        c: ByteBuf,
        v: u8,
    }

    fn int(n: i128) -> serde_json::Value {
        json!({"t": "int", "c": {"inner": n.to_le_bytes().to_vec()}})
    }
    fn bytes(b: &[u8]) -> serde_json::Value {
        json!({"t": "bytes", "c": b})
    }

    /// Built the way proton-pass-common writes one (rmp_serde named).
    fn sample(d: &[u8; 32], tamper: bool) -> Vec<u8> {
        let secret = p256::SecretKey::from_slice(d).unwrap();
        let point = secret.public_key().to_encoded_point(false);
        let mut y = point.y().unwrap().to_vec();
        if tamper {
            y[0] ^= 1;
        }
        let pk = Pk {
            key: Key {
                kty: json!({"t": "assign", "c": "EC2"}),
                kid: ByteBuf::new(),
                alg: Some(json!({"t": "assign", "c": "ES256"})),
                kops: vec![],
                biv: ByteBuf::new(),
                par: vec![
                    (json!({"t": "int", "c": 1}), int(2)),
                    (json!({"t": "int", "c": -1}), int(1)),
                    (json!({"t": "int", "c": -2}), bytes(point.x().unwrap())),
                    (json!({"t": "int", "c": -3}), bytes(&y)),
                    (json!({"t": "int", "c": -4}), bytes(d)),
                ],
                _p: std::marker::PhantomData,
            },
            cid: ByteBuf::from(vec![1, 2, 3]),
            rid: "example.com",
            uhd: Some(ByteBuf::from(vec![9])),
            cnt: Some(0),
        };
        let inner = rmp_serde::to_vec_named(&pk).unwrap();
        rmp_serde::to_vec_named(&Outer { c: ByteBuf::from(inner), v: 1 }).unwrap()
    }

    #[test]
    fn a_proton_passkey_becomes_a_credential() {
        let (rp, c) = credential(&sample(&[7u8; 32], false)).unwrap();
        assert_eq!(rp, "example.com");
        assert_eq!(c["credentialId"], "AQID");
        assert_eq!(c["userHandle"], "CQ==");
        assert_eq!(c["isResidentCredential"], true);
        assert!(c["privateKey"].as_str().unwrap().len() > 100);
    }

    #[test]
    fn a_mismatched_public_key_is_refused() {
        assert!(credential(&sample(&[7u8; 32], true)).is_err());
    }
}
