// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    // This is it. This is the entire file's logic.
    // It just builds the window manager and runs it.
    tauri::Builder::default()
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
