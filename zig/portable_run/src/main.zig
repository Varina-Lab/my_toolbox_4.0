const std = @import("std");
const windows = std.os.windows;

// --- Win32 API (Phiên bản W - Hỗ trợ Unicode 100%) ---
extern "user32" fn MessageBoxW(hWnd: ?windows.HWND, lpText: [*:0]const u16, lpCaption: [*:0]const u16, uType: c_uint) callconv(.C) c_int;
extern "comdlg32" fn GetOpenFileNameW(lpofn: *OPENFILENAMEW) callconv(.C) windows.BOOL;
extern "kernel32" fn SetEnvironmentVariableW(lpName: [*:0]const u16, lpValue: [*:0]const u16) callconv(.C) windows.BOOL;

const MB_YESNO: c_uint = 4;
const MB_ICONQUESTION: c_uint = 32;
const MB_ICONERROR: c_uint = 16;
const IDYES: c_int = 6;

const OPENFILENAMEW = extern struct {
    lStructSize: windows.DWORD,
    hwndOwner: ?windows.HWND,
    hInstance: ?windows.HINSTANCE,
    lpstrFilter: ?[*:0]const u16,
    lpstrCustomFilter: ?[*:0]u16,
    nMaxCustFilter: windows.DWORD,
    nFilterIndex: windows.DWORD,
    lpstrFile: ?[*:0]u16,
    nMaxFile: windows.DWORD,
    lpstrFileTitle: ?[*:0]u16,
    nMaxFileTitle: windows.DWORD,
    lpstrInitialDir: ?[*:0]const u16,
    lpstrTitle: ?[*:0]const u16,
    Flags: windows.DWORD,
    nFileOffset: windows.WORD,
    nFileExtension: windows.WORD,
    lpstrDefExt: ?[*:0]const u16,
    lCustData: windows.LPARAM,
    lpfnHook: ?*const anyopaque,
    lpTemplateName: ?[*:0]const u16,
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

        try setEnvW(self.allocator, "APPDATA", roam);
        try setEnvW(self.allocator, "LOCALAPPDATA", local);
        try setEnvW(self.allocator, "USERPROFILE", self.p_data);
        try setEnvW(self.allocator, "DOCUMENTS", docs);
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

// --- Helper chuyển đổi UTF-8 sang UTF-16LE cho Windows ---
fn setEnvW(allocator: std.mem.Allocator, name: []const u8, value: []const u8) !void {
    const name_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, name);
    defer allocator.free(name_w);
    const value_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, value);
    defer allocator.free(value_w);
    _ = SetEnvironmentVariableW(name_w.ptr, value_w.ptr);
}

fn askYesNo(allocator: std.mem.Allocator, title: []const u8, msg: []const u8) bool {
    const title_w = std.unicode.utf8ToUtf16LeAllocZ(allocator, title) catch return false;
    defer allocator.free(title_w);
    const msg_w = std.unicode.utf8ToUtf16LeAllocZ(allocator, msg) catch return false;
    defer allocator.free(msg_w);
    return MessageBoxW(null, msg_w.ptr, title_w.ptr, MB_YESNO | MB_ICONQUESTION) == IDYES;
}

fn showError(allocator: std.mem.Allocator, msg: []const u8) void {
    if (std.unicode.utf8ToUtf16LeAllocZ(allocator, msg)) |msg_w| {
        defer allocator.free(msg_w);
        const title_w = std.unicode.utf8ToUtf16LeAllocZ(allocator, "Application Error") catch return;
        defer allocator.free(title_w);
        _ = MessageBoxW(null, msg_w.ptr, title_w.ptr, MB_ICONERROR);
    } else |_| {}
}

fn pickExe(allocator: std.mem.Allocator) ![]const u8 {
    var filename_buf = [_:0]u16{0} ** 260;
    var ofn = std.mem.zeroes(OPENFILENAMEW);
    ofn.lStructSize = @sizeOf(OPENFILENAMEW);
    ofn.lpstrFile = &filename_buf;
    ofn.nMaxFile = 260;
    
    const filter = [_:0]u16{ 'E','x','e','c','u','t','a','b','l','e','s', 0, '*','.','e','x','e', 0, 0 };
    ofn.lpstrFilter = &filter;
    const title = [_:0]u16{ 'S','e','l','e','c','t',' ','E','X','E', 0 };
    ofn.lpstrTitle = &title;
    ofn.Flags = 0x00001000 | 0x00000004 | 0x00000008; // OFN_NOCHANGEDIR

    if (GetOpenFileNameW(&ofn) != 0) {
        const len = std.mem.indexOfScalar(u16, &filename_buf, 0) orelse 0;
        return try std.unicode.utf16LeToUtf8Alloc(allocator, filename_buf[0..len]);
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
// ENTRY POINT & LƯỚI BẮT LỖI
// =====================================================================
pub fn main() void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    
    mainImpl(arena.allocator()) catch |err| {
        if (err == error.Cancelled) return;
        var buf: [256]u8 = undefined;
        const err_msg = std.fmt.bufPrint(&buf, "Crashed with error: {any}", .{err}) catch "Fatal Error!";
        showError(arena.allocator(), err_msg);
    };
}

fn mainImpl(allocator: std.mem.Allocator) !void {
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
        selected_exe = try pickExe(allocator); 
    } else {
        showError(allocator, "No target executable found in the directory!");
        return;
    }

    try engine.bootstrap();

    var reg_before = std.StringHashMap(void).init(allocator);
    try snapshotRegistry(&reg_before, allocator);
    var folders_before = std.StringHashMap(void).init(allocator);
    try snapshotFolders(engine, &folders_before, allocator);

    try engine.setupEnv();

    // ĐÃ SỬA: Truyền thẳng selected_exe vào, không dùng path.join(".") nữa để tránh hỏng đường dẫn tuyệt đối!
    var child = std.process.Child.init(&[_][]const u8{selected_exe}, allocator);
    _ = try child.spawnAndWait();

    var reg_after = std.StringHashMap(void).init(allocator);
    try snapshotRegistry(&reg_after, allocator);
    var folders_after = std.StringHashMap(void).init(allocator);
    try snapshotFolders(engine, &folders_after, allocator);

    var selected_reg = std.ArrayList([]const u8).init(allocator);
    var reg_it = reg_after.keyIterator();
    while (reg_it.next()) |key| {
        if (!reg_before.contains(key.*) and !containsNoise(key.*)) {
            const msg = try std.fmt.allocPrint(allocator, "Found new Registry Key:\n{s}\n\nDo you want to make it portable?", .{key.*});
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
            
            const msg = try std.fmt.allocPrint(allocator, "Found new Folder in [{s}]:\n{s}\n\nDo you want to make it portable?", .{tag, name});
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

    // ĐÃ SỬA: Chạy thẳng EXE từ config (đã là UTF-8 sạch)
    var child = std.process.Child.init(&[_][]const u8{config.selected_exe}, engine.allocator);
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
    // ĐÃ SỬA: Dùng chcp 65001 ép cmd xuất kết quả UTF-8, chấm dứt hoàn toàn hiện tượng Mojibake khi đọc Registry!
    var child = std.process.Child.init(&[_][]const u8{ "cmd", "/c", "chcp 65001 >nul & reg query HKCU\\Software" }, allocator);
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
        try runSilentCmd(allocator, &[_][]const u8{ "cmd", "/c", "chcp 65001 >nul & reg", "export", key, temp_reg, "/y" });
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
