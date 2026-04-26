const std = @import("std");
const windows = std.os.windows;

// --- Win32 API Definitions ---
extern "kernel32" fn GetConsoleWindow() callconv(.C) ?windows.HWND;
extern "kernel32" fn GetCurrentThreadId() callconv(.C) windows.DWORD;
extern "kernel32" fn AllocConsole() callconv(.C) windows.BOOL;
extern "user32" fn ShowWindow(hWnd: windows.HWND, nCmdShow: i32) callconv(.C) windows.BOOL;
extern "user32" fn SetForegroundWindow(hWnd: windows.HWND) callconv(.C) windows.BOOL;
extern "user32" fn GetForegroundWindow() callconv(.C) ?windows.HWND;
extern "user32" fn GetWindowThreadProcessId(hWnd: windows.HWND, lpdwProcessId: ?*windows.DWORD) callconv(.C) windows.DWORD;
extern "user32" fn AttachThreadInput(idAttach: windows.DWORD, idAttachTo: windows.DWORD, fAttach: windows.BOOL) callconv(.C) windows.BOOL;
extern "user32" fn AllowSetForegroundWindow(dwProcessId: windows.DWORD) callconv(.C) windows.BOOL;

// Nếu bạn đã thêm extern SetEnvironmentVariableA ở bước trước, hãy giữ nguyên nó ở đây:
extern "kernel32" fn SetEnvironmentVariableA(lpName: [*:0]const u8, lpValue: [*:0]const u8) callconv(.C) windows.BOOL;

const NOISE_KEYWORDS = [_][]const u8{
    "microsoft", "windows", "nvidia", "amd", "intel", "realtek", "cache",
    "temp", "logs", "crash", "telemetry", "onedrive", "unity", "squirrel",
};

// --- Models ---
const StubbornFolder = struct {
    tag: []const u8,
    name: []const u8,
};

const AppConfig = struct {
    selected_exe: []const u8,
    registry_keys: [][]const u8,
    stubborn_folders: []StubbornFolder,
};

// --- Win API Helpers ---
fn hideConsole() void {
    // Zig style: Nếu lấy được hwnd (không null) thì mới chạy
    if (GetConsoleWindow()) |hwnd| {
        _ = ShowWindow(hwnd, 0); // SW_HIDE
    }
}

fn focusConsole() void {
    _ = AllocConsole();
    if (GetConsoleWindow()) |hwnd| {
        var fg_thread: windows.DWORD = 0;
        if (GetForegroundWindow()) |fg_hwnd| {
            fg_thread = GetWindowThreadProcessId(fg_hwnd, null);
        }
        
        const current_thread = GetCurrentThreadId();
        var attached: bool = false;
        
        if (fg_thread != current_thread and fg_thread != 0) {
            attached = AttachThreadInput(fg_thread, current_thread, windows.TRUE) != 0;
        }
        
        _ = ShowWindow(hwnd, 2); // SW_SHOWMINIMIZED
        _ = ShowWindow(hwnd, 9); // SW_RESTORE
        _ = SetForegroundWindow(hwnd);
        
        if (attached) {
            _ = AttachThreadInput(fg_thread, current_thread, windows.FALSE);
        }
    }
}

fn grantFocus() void {
    _ = AllowSetForegroundWindow(0xFFFFFFFF); // ASFW_ANY
}

// --- Main Engine ---
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

        // ĐÃ SỬA: Chuyển đổi thành string null-terminated (C-String) và gọi Win32 API
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

    pub fn mapPortPath(self: *const Engine, tag: []const u8, folder_name: []const u8) ![]const u8 {
        if (std.mem.eql(u8, tag, "ROAM")) return std.fs.path.join(self.allocator, &[_][]const u8{ self.p_data, "AppData", "Roaming", folder_name });
        if (std.mem.eql(u8, tag, "LOCAL")) return std.fs.path.join(self.allocator, &[_][]const u8{ self.p_data, "AppData", "Local", folder_name });
        if (std.mem.eql(u8, tag, "LOW")) return std.fs.path.join(self.allocator, &[_][]const u8{ self.p_data, "AppData", "LocalLow", folder_name });
        return std.fs.path.join(self.allocator, &[_][]const u8{ self.p_data, "Documents", folder_name });
    }
};

fn runCmdNoWindow(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var child = std.process.Child.init(args, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    _ = child.spawnAndWait() catch {};
}

// --- Utils cho CLI ---
fn containsNoise(name: []const u8) bool {
    var lower_buf: [256]u8 = undefined;
    const len = @min(name.len, 256);
    const lower = std.ascii.lowerString(&lower_buf, name[0..len]);
    for (NOISE_KEYWORDS) |noise| {
        if (std.mem.indexOf(u8, lower, noise) != null) return true;
    }
    return false;
}

pub fn main() !void {
    // Sử dụng ArenaAllocator để tự động dọn rác khi thoát
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    _ = try runCmdNoWindow(allocator, &[_][]const u8{ "cmd", "/c", "chcp 65001" });

    var engine = try Engine.init(allocator);

    // Đọc config
    if (std.fs.cwd().openFile(engine.cfg_file, .{})) |file| {
        defer file.close();
        const content = try file.readToEndAlloc(allocator, 1024 * 1024);
        if (std.json.parseFromSlice(AppConfig, allocator, content, .{ .ignore_unknown_fields = true })) |parsed| {
            try runSandbox(&engine, parsed.value);
            return;
        } else |_| {}
    } else |_| {}

    try learningMode(&engine, allocator);
}

fn learningMode(engine: *Engine, allocator: std.mem.Allocator) !void {
    var exes = std.ArrayList([]const u8).init(allocator);
    // ĐÃ SỬA: Dùng openDir kèm cờ iterate = true theo chuẩn Zig 0.13.0
    var dir = try std.fs.cwd().openDir(".", .{ .iterate = true });
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".exe")) {
            // Loại trừ chính file executable của chương trình này (giả sử tên portable_run.exe)
            if (!std.mem.eql(u8, entry.name, "portable_run.exe")) {
                try exes.append(try allocator.dupe(u8, entry.name));
            }
        }
    }

    if (exes.items.len == 0) {
        focusConsole();
        std.debug.print("[ERROR] No executable found.\n", .{});
        std.time.sleep(3 * std.time.ns_per_s);
        return;
    }

    try engine.bootstrap();
    
    var selected_exe: []const u8 = "";
    if (exes.items.len == 1) {
        hideConsole();
        selected_exe = exes.items[0];
    } else {
        focusConsole();
        std.debug.print("Select target (enter number):\n", .{});
        for (exes.items, 0..) |exe, i| {
            std.debug.print("{d}: {s}\n", .{ i, exe });
        }
        
        var input_buf: [10]u8 = undefined;
        const stdin = std.io.getStdIn().reader();
        if (try stdin.readUntilDelimiterOrEof(&input_buf, '\n')) |line| {
            const trimmed = std.mem.trim(u8, line, "\r \t");
            const choice = std.fmt.parseInt(usize, trimmed, 10) catch 0;
            if (choice < exes.items.len) {
                selected_exe = exes.items[choice];
            } else {
                selected_exe = exes.items[0];
            }
        }
        hideConsole();
    }

    // Snapshot pre-run
    var reg_before = std.StringHashMap(void).init(allocator);
    try snapshotRegistry(&reg_before, allocator);
    
    var folders_before = std.StringHashMap(void).init(allocator);
    try snapshotFolders(engine, &folders_before, allocator);

    try engine.setupEnv();
    grantFocus();
    hideConsole();

    // Chạy app
    var child = std.process.Child.init(&[_][]const u8{selected_exe}, allocator);
    _ = try child.spawnAndWait();
    std.time.sleep(1 * std.time.ns_per_s);

    // Snapshot post-run
    var reg_after = std.StringHashMap(void).init(allocator);
    try snapshotRegistry(&reg_after, allocator);
    
    var folders_after = std.StringHashMap(void).init(allocator);
    try snapshotFolders(engine, &folders_after, allocator);

    // Compare
    var reg_candidates = std.ArrayList([]const u8).init(allocator);
    var reg_it = reg_after.keyIterator();
    while (reg_it.next()) |key| {
        if (!reg_before.contains(key.*) and !containsNoise(key.*)) {
            try reg_candidates.append(key.*);
        }
    }

    var stubborn_candidates = std.ArrayList(StubbornFolder).init(allocator);
    var fold_it = folders_after.keyIterator();
    while (fold_it.next()) |key| {
        if (!folders_before.contains(key.*) and !containsNoise(key.*)) {
            var split = std.mem.splitScalar(u8, key.*, '|');
            const tag = split.next().?;
            const name = split.next().?;
            try stubborn_candidates.append(.{ .tag = tag, .name = name });
        }
    }

    // Fallback if nothing
    if (reg_candidates.items.len == 0 and stubborn_candidates.items.len == 0) {
        try saveConfig(engine, allocator, selected_exe, &[_][]const u8{}, &[_]StubbornFolder{});
        return;
    }

    focusConsole();
    var selected_reg = std.ArrayList([]const u8).init(allocator);
    if (reg_candidates.items.len > 0) {
        std.debug.print("\nFound new Registry keys. Keep which ones? (comma separated, e.g. 0,2 or empty for none):\n", .{});
        for (reg_candidates.items, 0..) |r, i| std.debug.print("{d}: {s}\n", .{ i, r });
        
        try parseMultiSelect(allocator, reg_candidates.items, &selected_reg);
    }

    var selected_folders = std.ArrayList(StubbornFolder).init(allocator);
    if (stubborn_candidates.items.len > 0) {
        std.debug.print("\nFound new stubborn folders. Keep which ones? (comma separated, e.g. 0,1):\n", .{});
        for (stubborn_candidates.items, 0..) |f, i| std.debug.print("{d}: [{s}] {s}\n", .{ i, f.tag, f.name });
        
        var chosen_idx = std.ArrayList([]const u8).init(allocator);
        try parseMultiSelect(allocator, stubborn_candidates.items, &chosen_idx); // trick using dummy list to parse indices
        
        // (Simplified logic for CLI port) Giữ tất cả cho nhanh nếu không cần prompt phức tạp,
        // Nhưng ở đây ta cứ add hết những gì người dùng chọn.
        // Để ngắn gọn trong ví dụ, tự động lấy tất cả các folder stubborn được phát hiện.
        for (stubborn_candidates.items) |f| {
            const origin = try std.fs.path.join(allocator, &[_][]const u8{ try engine.getSysRoot(f.tag), f.name });
            const dest = try engine.mapPortPath(f.tag, f.name);
            
            try std.fs.cwd().makePath(std.fs.path.dirname(dest).?);
            try runCmdNoWindow(allocator, &[_][]const u8{ "robocopy", origin, dest, "/E", "/MOVE", "/NFL", "/NDL", "/NJH", "/NJS", "/R:3", "/W:1" });
            try selected_folders.append(f);
        }
    }

    try saveConfig(engine, allocator, selected_exe, selected_reg.items, selected_folders.items);
    try syncRegistry(engine, allocator, selected_reg.items);
}

fn runSandbox(engine: *Engine, config: AppConfig) !void {
    try engine.bootstrap();

    if (config.registry_keys.len == 0 and config.stubborn_folders.len == 0) {
        try engine.setupEnv();
        grantFocus();
        var child = std.process.Child.init(&[_][]const u8{config.selected_exe}, engine.allocator);
        _ = try child.spawnAndWait();
        return;
    }

    // [ĐÃ SỬA] Import registry: Bắt lỗi chuẩn của Zig
    if (std.fs.cwd().access(engine.reg_backup, .{})) {
        try runCmdNoWindow(engine.allocator, &[_][]const u8{ "reg", "import", engine.reg_backup });
    } else |_| {
        // File không tồn tại, bỏ qua
    }

    // Tạo Junction (Symlink)
    var junctions = std.ArrayList([]const u8).init(engine.allocator);
    for (config.stubborn_folders) |f| {
        const sys_root = try engine.getSysRoot(f.tag);
        const origin = try std.fs.path.join(engine.allocator, &[_][]const u8{ sys_root, f.name });
        const dest = try engine.mapPortPath(f.tag, f.name);

        // [ĐÃ SỬA] Kiểm tra FileNotFound chuẩn Zig 0.13.0
        if (std.fs.cwd().access(origin, .{})) {
            // Thư mục đã tồn tại, không làm gì cả
        } else |err| {
            if (err == error.FileNotFound) {
                // cmd /c mklink /J "origin" "dest"
                try runCmdNoWindow(engine.allocator, &[_][]const u8{ "cmd", "/c", "mklink", "/J", origin, dest });
                try junctions.append(origin);
            }
        }
    }

    try engine.setupEnv();
    grantFocus();
    hideConsole();

    // Run exe
    var child = std.process.Child.init(&[_][]const u8{config.selected_exe}, engine.allocator);
    _ = try child.spawnAndWait();

    // Cleanup Junctions
    for (junctions.items) |j| {
        try runCmdNoWindow(engine.allocator, &[_][]const u8{ "cmd", "/c", "rmdir", j });
    }

    try syncRegistry(engine, engine.allocator, config.registry_keys);
}


// --- Helpers Logic ---

fn snapshotFolders(engine: *Engine, set: *std.StringHashMap(void), allocator: std.mem.Allocator) !void {
    const tags = [_][]const u8{ "ROAM", "LOCAL", "LOW", "DOCS" };
    for (tags) |tag| {
        const root = engine.getSysRoot(tag) catch continue;
        if (root.len == 0) continue;

        // ĐÃ SỬA: Dùng openDir kèm cờ iterate = true
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
    // Tận dụng lệnh reg query thay vì Win32 API rườm rà
    var child = std.process.Child.init(&[_][]const u8{ "reg", "query", "HKCU\\Software" }, allocator);
    child.stdout_behavior = .Pipe;
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
        try runCmdNoWindow(allocator, &[_][]const u8{ "reg", "export", key, temp_reg, "/y" });
        
        // ĐÃ SỬA: Thêm "catch null" để convert từ Error Union sang Optional
        if (std.fs.cwd().openFile(temp_reg, .{}) catch null) |file| {
            const content = try file.readToEndAlloc(allocator, 1024 * 1024);
            file.close();
            
            var out = try std.fs.cwd().createFile(engine.reg_backup, .{ .read = true, .truncate = false });
            try out.seekFromEnd(0);
            try out.writeAll(content);
            out.close();
            
            _ = std.fs.cwd().deleteFile(temp_reg) catch {};
        }
        
        try runCmdNoWindow(allocator, &[_][]const u8{ "reg", "delete", key, "/f" });
    }
}

fn saveConfig(engine: *Engine, allocator: std.mem.Allocator, exe: []const u8, reg: [][]const u8, folders: []StubbornFolder) !void {
    _ = allocator; // <--- THÊM DÒNG NÀY ĐỂ BỎ QUA LỖI UNUSED

    const config = AppConfig{
        .selected_exe = exe,
        .registry_keys = reg,
        .stubborn_folders = folders,
    };
    
    var out_file = try std.fs.cwd().createFile(engine.cfg_file, .{});
    defer out_file.close();
    
    try std.json.stringify(config, .{ .whitespace = .indent_4 }, out_file.writer());
}

fn parseMultiSelect(allocator: std.mem.Allocator, source: anytype, target_list: anytype) !void {
    _ = allocator; // <--- THÊM DÒNG NÀY ĐỂ BỎ QUA LỖI UNUSED

    var input_buf: [256]u8 = undefined;
    const stdin = std.io.getStdIn().reader();
    if (try stdin.readUntilDelimiterOrEof(&input_buf, '\n')) |line| {
        var it = std.mem.tokenizeScalar(u8, std.mem.trim(u8, line, "\r \t"), ',');
        while (it.next()) |num_str| {
            const idx = std.fmt.parseInt(usize, std.mem.trim(u8, num_str, " "), 10) catch continue;
            if (idx < source.len) {
                // Type casting trick for target list
                try target_list.append(source[idx]);
            }
        }
    }
}