const std = @import("std");
const windows = std.os.windows;

// --- Win32 API Definitions ---
extern "user32" fn MessageBoxA(hWnd: ?windows.HWND, lpText: [*:0]const u8, lpCaption: [*:0]const u8, uType: c_uint) callconv(.C) c_int;
extern "comdlg32" fn GetOpenFileNameA(lpofn: *OPENFILENAMEA) callconv(.C) windows.BOOL;
extern "kernel32" fn SetEnvironmentVariableA(lpName: [*:0]const u8, lpValue: [*:0]const u8) callconv(.C) windows.BOOL;

const MB_YESNO: c_uint = 4;
const MB_ICONQUESTION: c_uint = 32;
const MB_ICONERROR: c_uint = 16;
const IDYES: c_int = 6;

const OPENFILENAMEA = extern struct {
    lStructSize: windows.DWORD,
    hwndOwner: ?windows.HWND,
    hInstance: ?windows.HINSTANCE,
    lpstrFilter: ?[*:0]const u8,
    lpstrCustomFilter: ?[*:0]u8,
    nMaxCustFilter: windows.DWORD,
    nFilterIndex: windows.DWORD,
    lpstrFile: ?[*:0]u8,
    nMaxFile: windows.DWORD,
    lpstrFileTitle: ?[*:0]u8,
    nMaxFileTitle: windows.DWORD,
    lpstrInitialDir: ?[*:0]const u8,
    lpstrTitle: ?[*:0]const u8,
    Flags: windows.DWORD,
    nFileOffset: windows.WORD,
    nFileExtension: windows.WORD,
    lpstrDefExt: ?[*:0]const u8,
    lCustData: windows.LPARAM,
    lpfnHook: ?*const anyopaque,
    lpTemplateName: ?[*:0]const u8,
    pvReserved: ?*anyopaque,
    dwReserved: windows.DWORD,
    FlagsEx: windows.DWORD,
};

const NOISE_KEYWORDS = [_][]const u8{
    "microsoft", "windows", "nvidia", "amd", "intel", "realtek", "cache",
    "temp", "logs", "crash", "telemetry", "onedrive", "unity", "squirrel",
};

const StubbornFolder = struct { tag: []const u8, name: []const u8 };
const AppConfig = struct {
    selected_exe: []const u8,
    registry_keys: [][]const u8,
    stubborn_folders: []StubbornFolder,
};

const Engine = struct {
    allocator: std.mem.Allocator,
    p_data: []const u8,
    cfg_file: []const u8,
    reg_backup: []const u8,

    pub fn init(allocator: std.mem.Allocator) !Engine {
        const cwd = try std.process.getCwdAlloc(allocator);
        const p_data = try std.fs.path.join(allocator, &[_][]const u8{ cwd, "Portable_Data" });
        const config_dir = try std.fs.path.join(allocator, &[_][]const u8{ p_data, "config" });
        const reg_dir = try std.fs.path.join(allocator, &[_][]const u8{ p_data, "Registry" });
        
        return Engine{
            .allocator = allocator,
            .p_data = p_data,
            .cfg_file = try std.fs.path.join(allocator, &[_][]const u8{ config_dir, "config.json" }),
            .reg_backup = try std.fs.path.join(allocator, &[_][]const u8{ reg_dir, "data.reg" }),
        };
    }

    pub fn bootstrap(self: *const Engine) !void {
        try std.fs.cwd().makePath(try std.fs.path.join(self.allocator, &[_][]const u8{ self.p_data, "config" }));
        try std.fs.cwd().makePath(try std.fs.path.join(self.allocator, &[_][]const u8{ self.p_data, "Registry" }));
    }

    pub fn setupEnv(self: *const Engine) !void {
        const roam = try std.fs.path.join(self.allocator, &[_][]const u8{ self.p_data, "AppData", "Roaming" });
        const local = try std.fs.path.join(self.allocator, &[_][]const u8{ self.p_data, "AppData", "Local" });
        const docs = try std.fs.path.join(self.allocator, &[_][]const u8{ self.p_data, "Documents" });

        try std.fs.cwd().makePath(roam);
        try std.fs.cwd().makePath(local);
        try std.fs.cwd().makePath(docs);

        _ = SetEnvironmentVariableA("APPDATA", try self.allocator.dupeZ(u8, roam));
        _ = SetEnvironmentVariableA("LOCALAPPDATA", try self.allocator.dupeZ(u8, local));
        _ = SetEnvironmentVariableA("USERPROFILE", try self.allocator.dupeZ(u8, self.p_data));
        _ = SetEnvironmentVariableA("DOCUMENTS", try self.allocator.dupeZ(u8, docs));
    }

    pub fn getSysRoot(self: *const Engine, tag: []const u8) ![]const u8 {
        if (std.mem.eql(u8, tag, "ROAM")) return std.process.getEnvVarOwned(self.allocator, "APPDATA") catch "";
        if (std.mem.eql(u8, tag, "LOCAL")) return std.process.getEnvVarOwned(self.allocator, "LOCALAPPDATA") catch "";
        if (std.mem.eql(u8, tag, "LOW")) {
            const local = std.process.getEnvVarOwned(self.allocator, "LOCALAPPDATA") catch return "";
            return try std.fs.path.join(self.allocator, &[_][]const u8{ std.fs.path.dirname(local).?, "LocalLow" });
        }
        if (std.mem.eql(u8, tag, "DOCS")) {
            const profile = std.process.getEnvVarOwned(self.allocator, "USERPROFILE") catch return "";
            return try std.fs.path.join(self.allocator, &[_][]const u8{ profile, "Documents" });
        }
        return "";
    }
};

fn askYesNo(allocator: std.mem.Allocator, title: []const u8, msg: []const u8) bool {
    const msg_z = allocator.dupeZ(u8, msg) catch return false;
    const title_z = allocator.dupeZ(u8, title) catch return false;
    return MessageBoxA(null, msg_z, title_z, MB_YESNO | MB_ICONQUESTION) == IDYES;
}

fn pickExe(allocator: std.mem.Allocator) ![]const u8 {
    var filename_buf = [_:0]u8{0} ** 260;
    var ofn = std.mem.zeroes(OPENFILENAMEA);
    ofn.lStructSize = @sizeOf(OPENFILENAMEA);
    ofn.lpstrFile = &filename_buf;
    ofn.nMaxFile = 260;
    const filter = "Executables\x00*.exe\x00\x00";
    ofn.lpstrFilter = filter;
    // Thêm OFN_NOCHANGEDIR để Hộp thoại không tự đổi thư mục hiện tại của tiến trình
    ofn.Flags = 0x00001000 | 0x00000004 | 0x00000008; 
    ofn.lpstrTitle = "Select the Application to make Portable";

    if (GetOpenFileNameA(&ofn) != 0) {
        return try allocator.dupe(u8, std.mem.sliceTo(&filename_buf, 0));
    }
    return error.Cancelled;
}

fn runSilentCmd(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var child = std.process.Child.init(args, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    _ = try child.spawnAndWait();
}

fn containsNoise(name: []const u8) bool {
    var lower_buf: [256]u8 = undefined;
    const len = @min(name.len, 256);
    const lower = std.ascii.lowerString(&lower_buf, name[0..len]);
    for (NOISE_KEYWORDS) |noise| {
        if (std.mem.indexOf(u8, lower, noise) != null) return true;
    }
    return false;
}

// =====================================================================
// LƯỚI BẮT LỖI TOÀN CẦU (GLOBAL ERROR HANDLER)
// Ngăn chặn "cái chết im lặng", hiển thị Popup nếu có lỗi xảy ra!
// =====================================================================
pub fn main() void {
    mainImpl() catch |err| {
        var buf: [256]u8 = undefined;
        // Bắt lỗi và in ra MessageBox
        const msg = std.fmt.bufPrintZ(&buf, "Program Crashed!\nError Code: {any}", .{err}) catch "Fatal Error!";
        _ = MessageBoxA(null, msg, "Critical Error", MB_ICONERROR);
    };
}

fn mainImpl() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var engine = try Engine.init(allocator);

    if (std.fs.cwd().openFile(engine.cfg_file, .{})) |file| {
        const content = try file.readToEndAlloc(allocator, 1024 * 1024);
        file.close();
        if (std.json.parseFromSlice(AppConfig, allocator, content, .{ .ignore_unknown_fields = true })) |parsed| {
            try runSandbox(&engine, parsed.value);
            return;
        } else |_| {}
    } else |_| {}

    try learningMode(&engine, allocator);
}

fn learningMode(engine: *Engine, allocator: std.mem.Allocator) !void {
    const self_path = try std.fs.selfExePathAlloc(allocator);
    const self_name = std.fs.path.basename(self_path);

    var exes = std.ArrayList([]const u8).init(allocator);
    var dir = try std.fs.cwd().openDir(".", .{ .iterate = true });
    
    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".exe")) {
            if (!std.mem.eql(u8, entry.name, self_name)) {
                try exes.append(try allocator.dupe(u8, entry.name));
            }
        }
    }
    dir.close();

    var selected_exe: []const u8 = "";
    if (exes.items.len == 1) {
        selected_exe = exes.items[0];
    } else if (exes.items.len > 1) {
        selected_exe = pickExe(allocator) catch return; 
    } else {
        _ = MessageBoxA(null, "No target executable found in the directory!", "Error", MB_ICONERROR);
        return;
    }

    try engine.bootstrap();

    var reg_before = std.StringHashMap(void).init(allocator);
    try snapshotRegistry(&reg_before, allocator);
    var folders_before = std.StringHashMap(void).init(allocator);
    try snapshotFolders(engine, &folders_before, allocator);

    try engine.setupEnv();

    // ĐÃ SỬA: Ép đường dẫn thành ./app.exe để chạy an toàn
    const run_path = try std.fs.path.join(allocator, &[_][]const u8{ ".", selected_exe });
    var child = std.process.Child.init(&[_][]const u8{run_path}, allocator);
    _ = try child.spawnAndWait();
    std.time.sleep(1 * std.time.ns_per_s);

    var reg_after = std.StringHashMap(void).init(allocator);
    try snapshotRegistry(&reg_after, allocator);
    var folders_after = std.StringHashMap(void).init(allocator);
    try snapshotFolders(engine, &folders_after, allocator);

    var selected_reg = std.ArrayList([]const u8).init(allocator);
    var reg_it = reg_after.keyIterator();
    while (reg_it.next()) |key| {
        if (!reg_before.contains(key.*) and !containsNoise(key.*)) {
            const msg = try std.fmt.allocPrintZ(allocator, "Found new Registry Key:\n{s}\n\nDo you want to make it portable?", .{key.*});
            if (askYesNo(allocator, "Registry Detected", msg)) {
                try selected_reg.append(key.*);
            }
        }
    }

    var selected_folders = std.ArrayList(StubbornFolder).init(allocator);
    var fold_it = folders_after.keyIterator();
    while (fold_it.next()) |key| {
        if (!folders_before.contains(key.*) and !containsNoise(key.*)) {
            var split = std.mem.splitScalar(u8, key.*, '|');
            const tag = split.next().?;
            const name = split.next().?;
            
            const msg = try std.fmt.allocPrintZ(allocator, "Found new Folder in [{s}]:\n{s}\n\nDo you want to make it portable?", .{tag, name});
            if (askYesNo(allocator, "Folder Detected", msg)) {
                const origin = try std.fs.path.join(allocator, &[_][]const u8{ try engine.getSysRoot(tag), name });
                const dest = try std.fs.path.join(allocator, &[_][]const u8{ engine.p_data, tag, name });
                
                try std.fs.cwd().makePath(std.fs.path.dirname(dest).?);
                try runSilentCmd(allocator, &[_][]const u8{ "robocopy", origin, dest, "/E", "/MOVE", "/NFL", "/NDL", "/NJH", "/NJS", "/NC", "/NS", "/NP" });
                try selected_folders.append(.{ .tag = tag, .name = name });
            }
        }
    }

    try saveConfig(engine, allocator, selected_exe, selected_reg.items, selected_folders.items);
    try syncRegistry(engine, allocator, selected_reg.items);
}

fn runSandbox(engine: *Engine, config: AppConfig) !void {
    try engine.bootstrap();

    if (std.fs.cwd().access(engine.reg_backup, .{})) {
        try runSilentCmd(engine.allocator, &[_][]const u8{ "reg", "import", engine.reg_backup });
    } else |_| {}

    var junctions = std.ArrayList([]const u8).init(engine.allocator);
    for (config.stubborn_folders) |f| {
        const sys_root = try engine.getSysRoot(f.tag);
        const origin = try std.fs.path.join(engine.allocator, &[_][]const u8{ sys_root, f.name });
        const dest = try std.fs.path.join(engine.allocator, &[_][]const u8{ engine.p_data, f.tag, f.name });

        if (std.fs.cwd().access(origin, .{})) {} else |err| {
            if (err == error.FileNotFound) {
                try runSilentCmd(engine.allocator, &[_][]const u8{ "cmd", "/c", "mklink", "/J", origin, dest });
                try junctions.append(origin);
            }
        }
    }

    try engine.setupEnv();

    // ĐÃ SỬA: Ép đường dẫn thành ./app.exe
    const run_path = try std.fs.path.join(engine.allocator, &[_][]const u8{ ".", config.selected_exe });
    var child = std.process.Child.init(&[_][]const u8{run_path}, engine.allocator);
    _ = try child.spawnAndWait();

    for (junctions.items) |j| {
        try runSilentCmd(engine.allocator, &[_][]const u8{ "cmd", "/c", "rmdir", j });
    }

    try syncRegistry(engine, engine.allocator, config.registry_keys);
}

fn snapshotFolders(engine: *Engine, set: *std.StringHashMap(void), allocator: std.mem.Allocator) !void {
    const tags = [_][]const u8{ "ROAM", "LOCAL", "LOW", "DOCS" };
    for (tags) |tag| {
        const root = engine.getSysRoot(tag) catch continue;
        if (root.len == 0) continue;
        
        var dir = std.fs.cwd().openDir(root, .{ .iterate = true }) catch continue;
        defer dir.close();
        var it = dir.iterate();
        
        while (try it.next()) |entry| {
            if (entry.kind == .directory) {
                const key = try std.fmt.allocPrint(allocator, "{s}|{s}", .{ tag, entry.name });
                try set.put(key, {});
            }
        }
    }
}

fn snapshotRegistry(set: *std.StringHashMap(void), allocator: std.mem.Allocator) !void {
    var child = std.process.Child.init(&[_][]const u8{ "reg", "query", "HKCU\\Software" }, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;
    
    try child.spawn();
    const stdout = try child.stdout.?.readToEndAlloc(allocator, 1024 * 1024);
    _ = try child.wait();
    
    var it = std.mem.tokenizeSequence(u8, stdout, "\r\n");
    while (it.next()) |line| {
        if (std.mem.startsWith(u8, line, "HKEY_CURRENT_USER\\Software\\")) {
            try set.put(line, {});
        }
    }
}

fn syncRegistry(engine: *Engine, allocator: std.mem.Allocator, keys: [][]const u8) !void {
    if (keys.len == 0) return;
    
    _ = std.fs.cwd().deleteFile(engine.reg_backup) catch {};
    const temp_reg = try std.fs.path.join(allocator, &[_][]const u8{ std.fs.path.dirname(engine.reg_backup).?, "port_tmp.reg" });
    
    for (keys) |key| {
        try runSilentCmd(allocator, &[_][]const u8{ "reg", "export", key, temp_reg, "/y" });
        if (std.fs.cwd().openFile(temp_reg, .{}) catch null) |file| {
            const content = try file.readToEndAlloc(allocator, 1024 * 1024);
            file.close();
            
            var out = try std.fs.cwd().createFile(engine.reg_backup, .{ .read = true, .truncate = false });
            try out.seekFromEnd(0);
            try out.writeAll(content);
            out.close();
            
            _ = std.fs.cwd().deleteFile(temp_reg) catch {};
        }
        try runSilentCmd(allocator, &[_][]const u8{ "reg", "delete", key, "/f" });
    }
}

fn saveConfig(engine: *Engine, allocator: std.mem.Allocator, exe: []const u8, reg: [][]const u8, folders: []StubbornFolder) !void {
    _ = allocator; 
    const config = AppConfig{
        .selected_exe = exe,
        .registry_keys = reg,
        .stubborn_folders = folders,
    };
    var out_file = try std.fs.cwd().createFile(engine.cfg_file, .{});
    defer out_file.close();
    try std.json.stringify(config, .{ .whitespace = .indent_4 }, out_file.writer());
}
