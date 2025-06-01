mod crypto;
mod vault;

use crypto::{derive_key, decrypt_vault, encrypt_vault};
use vault::{PasswordEntry, Vault};

use std::fs::{self, File};
use std::io::{self, Write};
use std::path::Path;
use std::time::{Duration, Instant};
use zeroize::Zeroizing;

const VAULT_PATH: &str = "vault.vault";

fn main() {
    println!("🔐 Vault CLI – Ultra Secure Password Manager");

    let master_password = prompt_hidden("Enter master password: ");
    let key = derive_key(&master_password);

    let mut vault = if Path::new(VAULT_PATH).exists() {
        let data = fs::read(VAULT_PATH).expect("Failed to read vault file.");
        decrypt_vault(&data, &key).unwrap_or_else(|_| {
            eprintln!("❌ Invalid password or corrupted vault.");
            std::process::exit(1);
        })
    } else {
        Vault { entries: vec![] }
    };

    let start_time = Instant::now();
    loop {
        if start_time.elapsed() > Duration::from_secs(120) {
            println!("⏳ Auto-locked due to inactivity.");
            break;
        }

        println!("\n1. Add new entry\n2. Show entries\n3. Delete entry\n4. Lock & exit");
        print!("Select an option: ");
        io::stdout().flush().unwrap();

        let mut selection = String::new();
        io::stdin().read_line(&mut selection).unwrap();

        match selection.trim() {
            "1" => {
                let account = prompt("Account name: ");
                let password = prompt_hidden("Password: ");
                vault.entries.push(PasswordEntry { account, password });
                println!("✅ Entry saved.");
            }
            "2" => {
                for (i, entry) in vault.entries.iter().enumerate() {
                    println!("[{}] {} – {}", i + 1, entry.account, entry.password);
                }
            }
            "3" => {
                let index = prompt("Enter number to delete: ");
                if let Ok(i) = index.trim().parse::<usize>() {
                    if i > 0 && i <= vault.entries.len() {
                        vault.entries.remove(i - 1);
                        println!("🗑️ Entry deleted.");
                    } else {
                        println!("Invalid entry number.");
                    }
                }
            }
            "4" => break,
            _ => println!("❓ Invalid selection."),
        }
    }

    let encrypted = encrypt_vault(&vault, &key).expect("Encryption failed.");
    fs::write(VAULT_PATH, encrypted).expect("Failed to save vault.");
    println!("🔒 Vault locked and saved. Stay safe!");
}

fn prompt(msg: &str) -> String {
    print!("{}", msg);
    io::stdout().flush().unwrap();
    let mut input = String::new();
    io::stdin().read_line(&mut input).unwrap();
    input.trim().to_owned()
}

fn prompt_hidden(msg: &str) -> Zeroizing<String> {
    use rpassword::read_password;
    print!("{}", msg);
    io::stdout().flush().unwrap();
    let password = read_password().unwrap();
    Zeroizing::new(password)
}
