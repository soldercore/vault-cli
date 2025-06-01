use serde::{Serialize, Deserialize};
use zeroize::Zeroize;

#[derive(Serialize, Deserialize)]
pub struct Vault {
    pub entries: Vec<PasswordEntry>,
}

#[derive(Serialize, Deserialize)]
pub struct PasswordEntry {
    pub account: String,
    
    #[serde(with = "zeroize_serde")]
    pub password: Zeroizing<String>,
}

// Serde helper for zeroize
mod zeroize_serde {
    use serde::{self, Deserialize, Deserializer, Serializer};
    use zeroize::Zeroizing;

    pub fn serialize<S>(value: &Zeroizing<String>, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.serialize_str(&value)
    }

    pub fn deserialize<'de, D>(deserializer: D) -> Result<Zeroizing<String>, D::Error>
    where
        D: Deserializer<'de>,
    {
        let s = String::deserialize(deserializer)?;
        Ok(Zeroizing::new(s))
    }
}
