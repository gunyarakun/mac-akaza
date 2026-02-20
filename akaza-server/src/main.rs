mod handler;
mod jsonrpc;

use std::io::{self, BufRead, Write};
use std::path::Path;
use std::sync::{Arc, Mutex};

use anyhow::Result;
use libakaza::config::EngineConfig;
use libakaza::engine::bigram_word_viterbi_engine::BigramWordViterbiEngineBuilder;
use libakaza::graph::reranking::ReRankingWeights;
use libakaza::lm::system_bigram::MarisaSystemBigramLM;
use libakaza::lm::system_unigram_lm::MarisaSystemUnigramLM;
use libakaza::user_side_data::user_data::UserData;
use log::info;

fn main() -> Result<()> {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"))
        .target(env_logger::Target::Stderr)
        .init();

    let model_dir = match std::env::args().nth(1) {
        Some(path) => path,
        None => {
            eprintln!("Usage: akaza-server <model-directory>");
            std::process::exit(1);
        }
    };

    info!("Starting akaza-server with model: {}", model_dir);

    let user_data = Arc::new(Mutex::new(
        UserData::load_from_default_path().unwrap_or_default(),
    ));

    let config = EngineConfig {
        model: model_dir.clone(),
        dicts: vec![],
        dict_cache: true,
        reranking_weights: ReRankingWeights::default(),
    };

    let engine = BigramWordViterbiEngineBuilder::new(config)
        .user_data(user_data)
        .build()?;

    info!("Engine initialized successfully");

    let unigram_lm = MarisaSystemUnigramLM::load(&format!("{}/unigram.model", model_dir))?;
    let bigram_lm = MarisaSystemBigramLM::load(&format!("{}/bigram.model", model_dir))?;

    let basedir = xdg::BaseDirectories::with_prefix("akaza")?;
    let dict_path = basedir
        .place_data_file(Path::new("SKK-JISYO.user"))?
        .to_str()
        .unwrap()
        .to_string();

    let mut handler =
        handler::Handler::new(engine, dict_path, model_dir.clone(), unigram_lm, bigram_lm);

    let stdin = io::stdin();
    let mut stdout = io::stdout();

    for line in stdin.lock().lines() {
        let line = match line {
            Ok(l) => l,
            Err(e) => {
                log::error!("Failed to read stdin: {}", e);
                break;
            }
        };

        if line.is_empty() {
            continue;
        }

        let response = handler.handle_request(&line);
        writeln!(stdout, "{}", response)?;
        stdout.flush()?;
    }

    info!("akaza-server shutting down");
    Ok(())
}
