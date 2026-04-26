const std = @import("std");
const windows = std.os.windows;

// --- Win32 API Tối Giản ---
extern "kernel32" fn AllocConsole() callconv(.C) windows.BOOL;
extern "kernel32" fn FreeConsole() callconv(.C) windows.BOOL;
extern "kernel32" fn GetStdHandle(nStdHandle: windows.DWORD) callconv(.C) ?windows.HANDLE;
extern "kernel32" fn GetConsoleMode(hConsoleHandle: windows.HANDLE, lpMode: *windows.DWORD) callconv(.C) windows.BOOL;
extern "kernel32" fn SetConsoleMode(hConsoleHandle: windows.HANDLE, dwMode: windows.DWORD) callconv(.C) windows.BOOL;
extern "kernel32" fn WriteConsoleA(hOut: windows.HANDLE, lpBuf: [*]const u8, nChars: windows.DWORD, lpWritten: *windows.DWORD, lpRes: ?*anyopaque) callconv(.C) windows.BOOL;
extern "kernel32" fn WriteConsoleW(hOut: windows.HANDLE, lpBuf: [*]const u16, nChars: windows.DWORD, lpWritten: *windows.DWORD, lpRes: ?*anyopaque) callconv(.C) windows.BOOL;
extern "kernel32" fn ReadConsoleInputW(hIn: windows.HANDLE, lpBuf: *INPUT_RECORD, nLen: windows.DWORD, lpRead: *windows.DWORD) callconv(.C) windows.BOOL;
extern "kernel32" fn SetEnvironmentVariableW(lpName: [*:0]const u16, lpValue: [*:0]const u16) callconv(.C) windows.BOOL;

const STD_INPUT_HANDLE: windows.DWORD = @bitCast(@as(i32, -10));
const STD_OUTPUT_HANDLE: windows.DWORD = @bitCast(@as(i32, -11));
const ENABLE_VIRTUAL_TERMINAL_PROCESSING: windows.DWORD = 0x0004;

const INPUT_RECORD = extern struct {
    EventType: u16,
    pad: u16 = 0,
    Event: extern union {
        KeyEvent: extern struct {
            bKeyDown: i32,
            wRepeatCount: u16,
            wVirtualKeyCode: u16,
            wVirtualScanCode: u16,
            uChar: u16,
            dwControlKeyState: u32,
        },
        padding: [16]u8,
    },
};

const StubbornFolder = struct { tag: []const u8, name: []const u8 };
const AppConfig = struct {
    selected_exe: []const u8,
    registry_keys: [][]const u8,
    stubborn_folders: []StubbornFolder,
};

// =====================================================================
// TERMINAL UI (TUI) - Điều khiển bằng Lên/Xuống/Space/Enter
// =====================================================================
fn printTui(hOut: windows.HANDLE, comptime fmt: []const u8, args: anytype) void {
    var buf: [1024]u8 = undefined;
    if (std.fmt.bufPrint(&buf, fmt, args)) |str| {
        var written: windows.DWORD = 0;
        // Đã sửa lỗi ép kiểu @intCast của Zig 0.13.0
        _ = WriteConsoleA(hOut, str.ptr, @as(u32, @intCast(str.len)), &written, null);
    } else |_| {}
}

fn printTuiW(hOut: windows.HANDLE, allocator: std.mem.Allocator, str: []const u8) void {
    if (std.unicode.utf8ToUtf16LeAlloc(allocator, str)) |utf16| {
        defer allocator.free(utf16);
        var written: windows.DWORD = 0;
        _ = WriteConsoleW(hOut, utf16.ptr, @as(u32, @intCast(utf16.len)), &written, null);
    } else |_| {}
}

fn readKey(hIn: windows.HANDLE) !enum { Up, Down, Space, Enter, None } {
    var record: INPUT_RECORD = undefined;
    var read: windows.DWORD = 0;
    while (true) {
        if (ReadConsoleInputW(hIn, &record, 1, &read) == 0) return error.ReadFailed;
        if (read > 0 and record.EventType == 1 and record.Event.KeyEvent.bKeyDown != 0) {
            switch (record.Event.KeyEvent.wVirtualKeyCode) {
                0x26 => return .Up,
                0x28 => return .Down,
                0x20 => return .Space,
                0x0D => return .Enter,
                else => {},
            }
        }
    }
}

// Menu Chọn 1 (Lên/Xuống/Enter)
fn tuiSingleSelect(hIn: windows.HANDLE, hOut: windows.HANDLE, allocator: std.mem.Allocator, title: []const u8, items: [][]const u8) !usize {
    var sel: usize = 0;
    while (true) {
        printTui(hOut, "\x1b[2J\x1b[H\x1b[36m{s}\x1b[0m\r\n\r\n", .{title});
        for (items, 0..) |item, i| {
            if (i == sel) printTui(hOut, "\x1b[32m  > \x1b[0m", .{}) else printTui(hOut, "    ", .{});
            printTuiW(hOut, allocator, item);
            printTui(hOut, "\r\n", .{});
        }
        switch (try readKey(hIn)) {
            .Up => if (sel > 0) { sel -= 1; } else { sel = items.len - 1; },
            .Down => if (sel < items.len - 1) { sel += 1; } else { sel = 0; },
            .Enter => return sel,
            else => {},
        }
    }
}

// Menu Chọn Nhiều (Lên/Xuống/Space/Enter)
fn tuiMultiSelect(hIn: windows.HANDLE, hOut: windows.HANDLE, allocator: std.mem.Allocator, title: []const u8, items: [][]const u8, checked: []bool) !void {
    var sel: usize = 0;
    while (true) {
        printTui(hOut, "\x1b[2J\x1b[H\x1b[36m{s}\x1b[0m\r\n", .{title});
        printTui(hOut, "\x1b[90m(Nav: Up/Down | Toggle: Space | Confirm: Enter)\x1b[0m\r\n\r\n", .{});
        for (items, 0..) |item, i| {
            if (i == sel) printTui(hOut, "\x1b[32m  > \x1b[0m", .{}) else printTui(hOut, "    ", .{});
            if (checked[i]) printTui(hOut, "\x1b[32m[x] \x1b[0m", .{}) else printTui(hOut, "[ ] ", .{});
            printTuiW(hOut, allocator, item);
            printTui(hOut, "\r\n", .{});
        }
        switch (try readKey(hIn)) {
            .Up => if (sel > 0) { sel -= 1; } else { sel = items.len - 1; },
            .Down => if (sel < items.len - 1) { sel += 1; } else { sel = 0; },
            .Space => checked[sel] = !checked[sel],
            .Enter => return,
            else => {},
        }
    }
}

// =====================================================================
// CORE ENGINE LÔ-GIC
// =====================================================================
const Engine = struct {
    allocator: std.mem.Allocator,
    p_data: []const u8,
    cfg_file: []const u8,
    reg_backup: []const u8,

    pub fn init(allocator: std.mem.Allocator) !Engine {
        const cwd = try std.process.getCwdAlloc(allocator);
        const p_data = try std.fs.path.join(allocator, &[_][]const u8{ cwd, "Portable_Data" });
        return Engine{
            .allocator = allocator,
            .p_data = p_data,
            .cfg_file = try std.fs.path.join(allocator, &[_][]const u8{ p_data, "config", "config.json" }),
            .reg_backup = try std.fs.path.join(allocator, &[_][]const u8{ p_data, "Registry", "data.reg" }),
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

fn setEnvW(allocator: std.mem.Allocator, name: []const u8, value: []const u8) !void {
    const n_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, name);
    defer allocator.free(n_w);
    const v_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, value);
    defer allocator.free(v_w);
    _ = SetEnvironmentVariableW(n_w.ptr, v_w.ptr);
}

fn runSilentCmd(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var child = std.process.Child.init(args, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    _ = try child.spawnAndWait();
}

pub fn main() !void {
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
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".exe") and !std.mem.eql(u8, entry.name, self_name)) {
            try exes.append(try allocator.dupe(u8, entry.name));
        }
    }
    dir.close();

    if (exes.items.len == 0) return;

    var selected_exe: []const u8 = exes.items[0];
    if (exes.items.len > 1) {
        _ = AllocConsole(); // TRIỆU HỒI CONSOLE
        const hIn = GetStdHandle(STD_INPUT_HANDLE).?;
        const hOut = GetStdHandle(STD_OUTPUT_HANDLE).?;
        var mode: windows.DWORD = 0;
        _ = GetConsoleMode(hOut, &mode);
        _ = SetConsoleMode(hOut, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
        printTui(hOut, "\x1b[?25l", .{}); // Ẩn con trỏ

        const choice = try tuiSingleSelect(hIn, hOut, allocator, "Multiple EXEs found. Select main app:", exes.items);
        selected_exe = exes.items[choice];
        
        printTui(hOut, "\x1b[?25h", .{});
        _ = FreeConsole(); // TẮT CONSOLE NGAY LẬP TỨC
    }

    try engine.bootstrap();
    var reg_before = std.StringHashMap(void).init(allocator);
    try snapshotRegistry(&reg_before, allocator);
    var folders_before = std.StringHashMap(void).init(allocator);
    try snapshotFolders(engine, &folders_before, allocator);

    try engine.setupEnv();

    const run_path = try std.fs.path.join(allocator, &[_][]const u8{ ".", selected_exe });
    var child = std.process.Child.init(&[_][]const u8{run_path}, allocator);
    _ = try child.spawnAndWait();

    var reg_after = std.StringHashMap(void).init(allocator);
    try snapshotRegistry(&reg_after, allocator);
    var folders_after = std.StringHashMap(void).init(allocator);
    try snapshotFolders(engine, &folders_after, allocator);

    var tui_items = std.ArrayList([]const u8).init(allocator);
    var tui_checked = std.ArrayList(bool).init(allocator);

    var rit = reg_after.keyIterator();
    while (rit.next()) |key| {
        if (!reg_before.contains(key.*) and !containsNoise(key.*)) {
            try tui_items.append(try std.fmt.allocPrint(allocator, "[REG] {s}", .{key.*}));
            try tui_checked.append(true);
        }
    }
    var fit = folders_after.keyIterator();
    while (fit.next()) |key| {
        if (!folders_before.contains(key.*) and !containsNoise(key.*)) {
            var split = std.mem.splitScalar(u8, key.*, '|');
            try tui_items.append(try std.fmt.allocPrint(allocator, "[DIR] [{s}] {s}", .{split.next().?, split.next().?}));
            try tui_checked.append(true);
        }
    }

    var final_reg = std.ArrayList([]const u8).init(allocator);
    var final_folders = std.ArrayList(StubbornFolder).init(allocator);

    if (tui_items.items.len > 0) {
        _ = AllocConsole(); // TRIỆU HỒI CONSOLE
        const hIn = GetStdHandle(STD_INPUT_HANDLE).?;
        const hOut = GetStdHandle(STD_OUTPUT_HANDLE).?;
        var mode: windows.DWORD = 0;
        _ = GetConsoleMode(hOut, &mode);
        _ = SetConsoleMode(hOut, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
        printTui(hOut, "\x1b[?25l", .{});

        try tuiMultiSelect(hIn, hOut, allocator, "System changes detected! Select items:", tui_items.items, tui_checked.items);
        
        printTui(hOut, "\x1b[?25h", .{});
        _ = FreeConsole(); // TẮT CONSOLE

        var i: usize = 0;
        rit = reg_after.keyIterator();
        while (rit.next()) |key| {
            if (!reg_before.contains(key.*) and !containsNoise(key.*)) {
                if (tui_checked.items[i]) try final_reg.append(key.*);
                i += 1;
            }
        }
        fit = folders_after.keyIterator();
        while (fit.next()) |key| {
            if (!folders_before.contains(key.*) and !containsNoise(key.*)) {
                if (tui_checked.items[i]) {
                    var split = std.mem.splitScalar(u8, key.*, '|');
                    const tag = split.next().?;
                    const name = split.next().?;
                    const origin = try std.fs.path.join(allocator, &[_][]const u8{ try engine.getSysRoot(tag), name });
                    const dest = try std.fs.path.join(allocator, &[_][]const u8{ engine.p_data, tag, name });
                    try std.fs.cwd().makePath(std.fs.path.dirname(dest).?);
                    try runSilentCmd(allocator, &[_][]const u8{ "robocopy", origin, dest, "/E", "/MOVE", "/NFL", "/NDL", "/NJH", "/NJS", "/NC", "/NS", "/NP" });
                    try final_folders.append(.{ .tag = tag, .name = name });
                }
                i += 1;
            }
        }
    }

    try saveConfig(engine, allocator, selected_exe, final_reg.items, final_folders.items);
    try syncRegistry(engine, allocator, final_reg.items);
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
    const run_path = try std.fs.path.join(engine.allocator, &[_][]const u8{ ".", config.selected_exe });
    var child = std.process.Child.init(&[_][]const u8{run_path}, engine.allocator);
    _ = try child.spawnAndWait();

    for (junctions.items) |j| {
        try runSilentCmd(engine.allocator, &[_][]const u8{ "cmd", "/c", "rmdir", j });
    }
    try syncRegistry(engine, engine.allocator, config.registry_keys);
}

const NOISE_KEYWORDS = [_][]const u8{
    "microsoft", "windows", "nvidia", "amd", "intel", "realtek", "cache",
    "temp", "logs", "crash", "telemetry", "onedrive", "unity", "squirrel",
};

fn containsNoise(name: []const u8) bool {
    var lower_buf: [256]u8 = undefined;
    const len = @min(name.len, 256);
    const lower = std.ascii.lowerString(&lower_buf, name[0..len]);
    for (NOISE_KEYWORDS) |noise| {
        if (std.mem.indexOf(u8, lower, noise) != null) return true;
    }
    return false;
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
                try set.put(try std.fmt.allocPrint(allocator, "{s}|{s}", .{ tag, entry.name }), {});
            }
        }
    }
}

fn snapshotRegistry(set: *std.StringHashMap(void), allocator: std.mem.Allocator) !void {
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
    const config = AppConfig{ .selected_exe = exe, .registry_keys = reg, .stubborn_folders = folders };
    var out_file = try std.fs.cwd().createFile(engine.cfg_file, .{});
    defer out_file.close();
    try std.json.stringify(config, .{ .whitespace = .indent_4 }, out_file.writer());
}