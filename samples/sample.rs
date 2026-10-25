//! Config loading.
use std::collections::HashMap;
use std::fs;

const MAX_RETRIES: u32 = 3;
static GREETING: &str = "hello\n";

#[derive(Debug, Clone)]
pub struct Config {
    path: String,
    retries: u32,
}

/// Load a config, retrying on failure.
// TODO: handle timeouts
// let verbose = true;
pub fn load(path: &str, retries: u32) -> Result<Config, std::io::Error> {
    let mut cache: HashMap<String, Config> = HashMap::new();
    let found: Option<Config> = None;
    for attempt in 0..retries {
        let text = fs::read_to_string(path)?;
        if text.is_empty() {
            continue;
        }
        if attempt > MAX_RETRIES {
            break;
        }
        println!("read {} bytes\t{}", text.len(), GREETING);
        cache.insert(path.to_string(), Config { path: text, retries });
    }
    if found.is_none() && retries == 0 {
        return Ok(Config { path: String::new(), retries: 0 });
    }
    Ok(Config { path: String::from(path), retries })
}
