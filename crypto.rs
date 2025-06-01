use aes_gcm::{Aes256Gcm, KeyInit, Nonce};
use aes_gcm::aead::{Aead, OsRng};
use argon2::{Argon2, PasswordHasher};
use argon2::password_hash::{SaltString, PasswordHash, PasswordVerifier};
use hmac::{Hmac, Mac};
use sha2::Sha256;
use rand::RngCore;
use zeroize::Zeroizing;
use crate::vault::Vault;
use bincode;

type HmacSha256 = Hmac<Sha256>;

const SALT_LEN: usize = 16;
const NONCE_LEN: usize = 12;

pub fn derive_key(password: &str) -> [u8; 32] {
    let salt = SaltString::generate(&mut OsRng);
    let argon2 = Argon2::default();
    let hash = argon2.hash_password(password.as_bytes(), &salt)
        .expect("Key derivation failed")
        .hash.expect("Missing hash");

    let mut key = [0u8; 32];
    key.copy_from_slice(&hash.as_bytes()[..32]);
    key
}

pub fn encrypt_vault(vault: &Vault, key: &[u8; 32]) -> Result<Vec<u8>, &'static str> {
    let cipher = Aes256Gcm::new_from_slice(key).map_err(|_| "Invalid key")?;

    let nonce_bytes = {
        let mut buf = [0u8; NONCE_LEN];
        OsRng.fill_bytes(&mut buf);
        buf
    };
    let nonce = Nonce::from_slice(&nonce_bytes);

    let serialized = bincode::serialize(vault).map_err(|_| "Vault serialization failed")?;
    let ciphertext = cipher.encrypt(nonce, serialized.as_ref()).map_err(|_| "Encryption failed")?;

    let mut hmac = HmacSha256::new_from_slice(key).map_err(|_| "HMAC setup failed")?;
    hmac.update(&nonce_bytes);
    hmac.update(&ciphertext);
    let hmac_bytes = hmac.finalize().into_bytes();

    let mut result = Vec::new();
    result.extend_from_slice(&nonce_bytes);
    result.extend_from_slice(&hmac_bytes);
    result.extend_from_slice(&ciphertext);
    Ok(result)
}

pub fn decrypt_vault(data: &[u8], key: &[u8; 32]) -> Result<Vault, &'static str> {
    if data.len() < NONCE_LEN + 32 {
        return Err("Invalid data length");
    }

    let nonce = &data[..NONCE_LEN];
    let hmac_stored = &data[NONCE_LEN..NONCE_LEN + 32];
    let ciphertext = &data[NONCE_LEN + 32..];

    let mut hmac = HmacSha256::new_from_slice(key).map_err(|_| "HMAC setup failed")?;
    hmac.update(nonce);
    hmac.update(ciphertext);
    hmac.verify_slice(hmac_stored).map_err(|_| "HMAC mismatch")?;

    let cipher = Aes256Gcm::new_from_slice(key).map_err(|_| "Invalid key")?;
    let decrypted = cipher.decrypt(Nonce::from_slice(nonce), ciphertext).map_err(|_| "Decryption failed")?;

    let vault: Vault = bincode::deserialize(&decrypted).map_err(|_| "Vault deserialization failed")?;
    Ok(vault)
}
