#![windows_subsystem = "windows"]

use dialoguer::{theme::ColorfulTheme, MultiSelect, Select};
use serde::{Deserialize, Serialize};
use std::{
    collections::HashSet,
    env, ffi::c_void,
    fs::{self, File},
    io::{BufReader, Read, Write},
    path::{Path, PathBuf},
    process::Command,
    thread, time::Duration,
    os::windows::process::CommandExt,
};
use winreg::{enums::*, RegKey};

const CREATE_NO_WINDOW: u32 = 0x08000000;
const NOISE_KEYWORDS: &[&str] = &[
    "microsoft", "windows", "nvidia", "amd", "intel", "realtek", "cache", 
    "temp", "logs", "crash", "telemetry", "onedrive", "unity", "squirrel"
];

mod win_api {
    use super::*;
    
    #[link(name = "kernel32")]
    extern "system" {
        pub fn AllocConsole() -> i32;
        pub fn GetConsoleWindow() -> *mut c_void;
        pub fn GetCurrentThreadId() -> u32;
    }
    #[link(name = "user32")]
    extern "system" {
        pub fn ShowWindow(hwnd: *mut c_void, nCmdShow: i32) -> bool;
        pub fn SetForegroundWindow(hwnd: *mut c_void) -> bool;
        pub fn GetForegroundWindow() -> *mut c_void;
        pub fn GetWindowThreadProcessId(hwnd: *mut c_void, lpdwProcessId: *mut u32) -> u32;
        pub fn AttachThreadInput(idAttach: u32, idAttachTo: u32, fAttach: bool) -> bool;
    }
    pub fn hide() {
        unsafe {
            let hwnd = GetConsoleWindow();
            if !hwnd.is_null() { ShowWindow(hwnd, 0); } 
        }
    }
    pub fn focus() {
        unsafe {
            AllocConsole();
            let hwnd = GetConsoleWindow();
            
            if !hwnd.is_null() {
                let foreground_hwnd = GetForegroundWindow();
                let current_thread_id = GetCurrentThreadId();
                let foreground_thread_id = GetWindowThreadProcessId(foreground_hwnd, std::ptr::null_mut());
                
                let mut attached = false;
                if foreground_thread_id != current_thread_id {
                    attached = AttachThreadInput(foreground_thread_id, current_thread_id, true);
                }
                ShowWindow(hwnd, 2); 
                ShowWindow(hwnd, 9); 
                SetForegroundWindow(hwnd);
                if attached {
                    AttachThreadInput(foreground_thread_id, current_thread_id, false);
                }
            }
        }
    }
    pub fn grant_focus() {
        unsafe { 
            #[link(name = "user32")]
            extern "system" {
                fn AllowSetForegroundWindow(dwProcessId: u32) -> bool;
            }
            AllowSetForegroundWindow(0xFFFFFFFF); 
        }
    }
}

#[derive(Serialize, Deserialize, Default, Debug)]
struct AppConfig {
    selected_exe: String,
    registry_keys: Vec<String>,
    stubborn_folders: Vec<StubbornFolder>,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
struct StubbornFolder {
    tag: String,
    name: String,
}

struct Engine {
    root: PathBuf,
    p_data: PathBuf,
    cfg_file: PathBuf,
    reg_backup: PathBuf,
    sys_roots: Vec<(&'static str, PathBuf)>,
}

impl Engine {
    fn new() -> Self {
        let root = env::current_dir().unwrap();
        let p_data = root.join("Portable_Data");
        let sys_roots = vec![
            ("ROAM", env::var_os("APPDATA").map(PathBuf::from).unwrap()),
            ("LOCAL", env::var_os("LOCALAPPDATA").map(PathBuf::from).unwrap()),
            ("LOW", dirs::home_dir().unwrap().join("AppData").join("LocalLow")),
            ("DOCS", dirs::document_dir().unwrap_or(dirs::home_dir().unwrap().join("Documents"))),
        ];
        Self {
            root,
            p_data: p_data.clone(),
            cfg_file: p_data.join("config").join("config.json"),
            reg_backup: p_data.join("Registry").join("data.reg"),
            sys_roots,
        }
    }

    fn bootstrap(&self) -> std::io::Result<()> {
        fs::create_dir_all(self.p_data.join("config"))?;
        fs::create_dir_all(self.p_data.join("Registry"))?;
        Ok(())
    }

    fn map_port_path(&self, tag: &str, folder_name: &str) -> PathBuf {
        match tag {
            "ROAM" => self.p_data.join("AppData").join("Roaming").join(folder_name),
            "LOCAL" => self.p_data.join("AppData").join("Local").join(folder_name),
            "LOW" => self.p_data.join("AppData").join("LocalLow").join(folder_name),
            _ => self.p_data.join("Documents").join(folder_name),
        }
    }

    fn setup_env(&self) -> std::io::Result<()> {
        let roam = self.p_data.join("AppData").join("Roaming");
        let local = self.p_data.join("AppData").join("Local");
        let docs = self.p_data.join("Documents");
        if !roam.exists() { fs::create_dir_all(&roam)?; }
        if !local.exists() { fs::create_dir_all(&local)?; }
        if !docs.exists() { fs::create_dir_all(&docs)?; }
        env::set_var("APPDATA", roam);
        env::set_var("LOCALAPPDATA", local);
        env::set_var("USERPROFILE", &self.p_data);
        env::set_var("DOCUMENTS", docs);
        Ok(())
    }

    fn snapshot_folders(&self) -> HashSet<String> {
        let mut set = HashSet::with_capacity(512);
        for (tag, root) in &self.sys_roots {
            if let Ok(entries) = fs::read_dir(root) {
                for entry in entries.filter_map(|e| e.ok()) {
                    if let Ok(meta) = entry.metadata() {
                        if meta.is_dir() {
                            set.insert(format!("{}|{}", tag, entry.file_name().to_string_lossy()));
                        }
                    }
                }
            }
        }
        set
    }

    fn snapshot_registry(&self) -> HashSet<String> {
        let mut set = HashSet::with_capacity(1024);
        let hkcu = RegKey::predef(HKEY_CURRENT_USER);
        if let Ok(sw) = hkcu.open_subkey("Software") {
            for name in sw.enum_keys().filter_map(|x| x.ok()) {
                set.insert(format!("HKEY_CURRENT_USER\\Software\\{}", name));
            }
        }
        set
    }

    fn sync_registry(&self, keys: &[String]) -> std::io::Result<()> {
        if keys.is_empty() { return Ok(()); }
        if self.reg_backup.exists() { fs::remove_file(&self.reg_backup)?; }
        let temp_reg = env::temp_dir().join("port_tmp.reg");
        for key in keys {
            Command::new("reg").args(&["export", key, temp_reg.to_str().unwrap(), "/y"])
                .creation_flags(CREATE_NO_WINDOW).status()?;
            if temp_reg.exists() {
                let mut content = Vec::new();
                File::open(&temp_reg)?.read_to_end(&mut content)?;
                let mut out = fs::OpenOptions::new().append(true).create(true).open(&self.reg_backup)?;
                out.write_all(&content)?;
                let _ = fs::remove_file(&temp_reg);
            }
            Command::new("reg").args(&["delete", key, "/f"]).creation_flags(CREATE_NO_WINDOW).status()?;
        }
        Ok(())
    }
}

fn main() -> std::io::Result<()> {
    let _ = Command::new("cmd").args(&["/c", "chcp 65001"]).creation_flags(CREATE_NO_WINDOW).output();
    let engine = Engine::new();
    
    if engine.cfg_file.exists() {
        let mut file = File::open(&engine.cfg_file)?;
        let mut content = String::new();
        file.read_to_string(&mut content)?;
        if let Ok(config) = serde_json::from_str::<AppConfig>(&content) {
            run_sandbox(engine, config)?;
            return Ok(());
        }
    }
    
    learning_mode(engine)
}

fn learning_mode(engine: Engine) -> std::io::Result<()> {
    let current_exe_name = env::current_exe()
        .ok()
        .and_then(|p| p.file_name().map(|n| n.to_string_lossy().to_lowercase()));
    let mut exes: Vec<String> = fs::read_dir(".")?
        .filter_map(|e| e.ok())
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .filter(|n| {
            let lower = n.to_lowercase();
            lower.ends_with(".exe") && Some(lower) != current_exe_name
        })
        .collect();
    if exes.is_empty() {
        win_api::focus();
        println!("[ERROR] No executable found.");
        thread::sleep(Duration::from_secs(3));
        return Ok(()); 
    }
    
    engine.bootstrap()?;
    let selected_exe = if exes.len() == 1 {
        win_api::hide();
        exes.remove(0)
    } else {
        win_api::focus();
        let choice = Select::with_theme(&ColorfulTheme::default()).with_prompt("Select target").items(&exes).default(0).interact().unwrap();
        win_api::hide(); 
        exes.remove(choice)
    };
    let reg_before = engine.snapshot_registry();
    let folders_before = engine.snapshot_folders();
    engine.setup_env()?;
    win_api::grant_focus();
    win_api::hide();
    
    let mut child = Command::new(&selected_exe).spawn()?;
    child.wait()?;
    thread::sleep(Duration::from_secs(1));
    let reg_after = engine.snapshot_registry();
    let folders_after = engine.snapshot_folders();
    let reg_candidates: Vec<String> = reg_after.difference(&reg_before)
        .filter(|k| !NOISE_KEYWORDS.iter().any(|&n| k.to_lowercase().contains(n)))
        .cloned().collect();
    let mut stubborn_candidates = vec![];
    for (tag, root) in &engine.sys_roots {
        if let Ok(entries) = fs::read_dir(root) {
            for entry in entries.filter_map(|e| e.ok()) {
                let name = entry.file_name().to_string_lossy().into_owned();
                if NOISE_KEYWORDS.iter().any(|&n| name.to_lowercase().contains(n)) { continue; }
                let key = format!("{}|{}", tag, name);
                if !folders_before.contains(&key) && folders_after.contains(&key) {
                    stubborn_candidates.push(StubbornFolder { tag: tag.to_string(), name });
                }
            }
        }
    }
    if reg_candidates.is_empty() && stubborn_candidates.is_empty() {
        let config = AppConfig { selected_exe, registry_keys: vec![], stubborn_folders: vec![] };
        fs::write(&engine.cfg_file, serde_json::to_string_pretty(&config).unwrap())?;
        return Ok(());
    }
    win_api::focus();
    let mut selected_reg = vec![];
    if !reg_candidates.is_empty() {
        let chosen = MultiSelect::with_theme(&ColorfulTheme::default()).with_prompt("Select Registry?").items(&reg_candidates).interact().unwrap();
        for i in chosen { selected_reg.push(reg_candidates[i].clone()); }
    }
    let mut selected_folders = vec![];
    if !stubborn_candidates.is_empty() {
        let names: Vec<String> = stubborn_candidates.iter().map(|f| format!("[{}] {}", f.tag, f.name)).collect();
        let chosen = MultiSelect::with_theme(&ColorfulTheme::default()).with_prompt("Select Folders?").items(&names).interact().unwrap();
        for i in chosen {
            let f = stubborn_candidates[i].clone();
            let origin = engine.sys_roots.iter().find(|(t,_)| *t == f.tag).map(|(_,p)| p).unwrap().join(&f.name);
            let dest = engine.map_port_path(&f.tag, &f.name);
            
            fs::create_dir_all(dest.parent().unwrap())?;
            Command::new("robocopy").args(&[origin.to_str().unwrap(), dest.to_str().unwrap(), "/E", "/MOVE", "/NFL", "/NDL", "/NJH", "/NJS", "/R:3", "/W:1"])
                .creation_flags(CREATE_NO_WINDOW).status()?;
            selected_folders.push(f);
        }
    }
    let config = AppConfig { selected_exe, registry_keys: selected_reg.clone(), stubborn_folders: selected_folders };
    fs::write(&engine.cfg_file, serde_json::to_string_pretty(&config).unwrap())?;
    engine.sync_registry(&selected_reg)?;
    Ok(())
}

fn run_sandbox(engine: Engine, config: AppConfig) -> std::io::Result<()> {
    engine.bootstrap()?;
    if config.registry_keys.is_empty() && config.stubborn_folders.is_empty() {
        engine.setup_env()?;
        win_api::grant_focus();
        Command::new(&config.selected_exe).spawn()?;
        return Ok(());
    }
    if engine.reg_backup.exists() {
        Command::new("reg").args(&["import", engine.reg_backup.to_str().unwrap()]).creation_flags(CREATE_NO_WINDOW).status()?;
    }
    let mut junctions = vec![];
    for f in &config.stubborn_folders {
        let origin = engine.sys_roots.iter().find(|(t,_)| *t == f.tag).map(|(_,p)| p).unwrap().join(&f.name);
        let dest = engine.map_port_path(&f.tag, &f.name);
        if !origin.exists() {
            if let Ok(_) = junction::create(&dest, &origin) { junctions.push(origin); }
        }
    }
    engine.setup_env()?;
    win_api::grant_focus();
    win_api::hide();
    
    let mut child = Command::new(&config.selected_exe).spawn()?;
    child.wait()?;
    for j in junctions { let _ = fs::remove_dir(j); }
    engine.sync_registry(&config.registry_keys)?;
    Ok(())
}