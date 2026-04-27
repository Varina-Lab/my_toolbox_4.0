const std = @import("std");
const windows = std.os.windows;

const HWND = ?*anyopaque;

const NOISE_KEYWORDS = [_][]const u8{
    "microsoft",
    "windows",
    "nvidia",
    "amd",
    "intel",
    "realtek",
    "cache",
    "temp",
    "logs",
    "crash",
    "telemetry",
    "onedrive",
    "unity",
    "squirrel",
};

extern "kernel32" fn AllocConsole() callconv(windows.WINAPI) windows.BOOL;
extern "kernel32" fn GetConsoleWindow() callconv(windows.WINAPI) HWND;
extern "kernel32" fn GetCurrentThreadId() callconv(windows.WINAPI) u32;
extern "kernel32" fn SetEnvironmentVariableW(
    lpName: [*:0]const u16,
    lpValue: ?[*:0]const u16,
) callconv(windows.WINAPI) windows.BOOL;

extern "user32" fn ShowWindow(hwnd: HWND, nCmdShow: c_int) callconv(windows.WINAPI) windows.BOOL;
extern "user32" fn SetForegroundWindow(hwnd: HWND) callconv(windows.WINAPI) windows.BOOL;
extern "user32" fn GetForegroundWindow() callconv(windows.WINAPI) HWND;
extern "user32" fn GetWindowThreadProcessId(hwnd: HWND, lpdwProcessId: ?*u32) callconv(windows.WINAPI) u32;
extern "user32" fn AttachThreadInput(idAttach: u32, idAttachTo: u32, fAttach: windows.BOOL) callconv(windows.WINAPI) windows.BOOL;
extern "user32" fn AllowSetForegroundWindow(dwProcessId: u32) callconv(windows.WINAPI) windows.BOOL;

const SW_HIDE = 0;
const SW_MINIMIZE = 2;
const SW_RESTORE = 9;
const ASFW_ANY: u32 = 0xFFFFFFFF;

const StubbornFolder = struct {
    tag: []const u8,
    name: []const u8,
};

const AppConfig = struct {
    selected_exe: []const u8 = "",
    registry_keys: [][]const u8 = &.{},
    stubborn_folders: []StubbornFolder = &.{},
};

const SysRoot = struct {
    tag: []const u8,
    path: []const u8,
};

const Engine = struct {
    allocator: std.mem.Allocator,
    root: []const u8,
    p_data: []const u8,
    cfg_file: []const u8,
    reg_dir: []const u8,
    sys_roots: []SysRoot,

    fn init(allocator: std.mem.Allocator) !Engine {
        const root = try std.process.getCwdAlloc(allocator);

        const p_data = try joinPath(allocator, &.{ root, "Portable_Data" });
        const cfg_file = try joinPath(allocator, &.{ p_data, "config", "config.json" });
        const reg_dir = try joinPath(allocator, &.{ p_data, "Registry" });

        const home = std.process.getEnvVarOwned(allocator, "USERPROFILE") catch try allocator.dupe(u8, root);

        const appdata = std.process.getEnvVarOwned(allocator, "APPDATA") catch
            try joinPath(allocator, &.{ home, "AppData", "Roaming" });

        const localappdata = std.process.getEnvVarOwned(allocator, "LOCALAPPDATA") catch
            try joinPath(allocator, &.{ home, "AppData", "Local" });

        const low = try joinPath(allocator, &.{ home, "AppData", "LocalLow" });
        const docs = try joinPath(allocator, &.{ home, "Documents" });

        var roots = try allocator.alloc(SysRoot, 4);
        roots[0] = .{ .tag = "ROAM", .path = appdata };
        roots[1] = .{ .tag = "LOCAL", .path = localappdata };
        roots[2] = .{ .tag = "LOW", .path = low };
        roots[3] = .{ .tag = "DOCS", .path = docs };

        return .{
            .allocator = allocator,
            .root = root,
            .p_data = p_data,
            .cfg_file = cfg_file,
            .reg_dir = reg_dir,
            .sys_roots = roots,
        };
    }

    fn bootstrap(self: *const Engine) !void {
        try ensureDir(self.p_data);
        try ensureDir(try joinPath(self.allocator, &.{ self.p_data, "config" }));
        try ensureDir(self.reg_dir);
    }

    fn mapPortPath(self: *const Engine, tag: []const u8, folder_name: []const u8) ![]const u8 {
        if (std.mem.eql(u8, tag, "ROAM")) {
            return joinPath(self.allocator, &.{ self.p_data, "AppData", "Roaming", folder_name });
        } else if (std.mem.eql(u8, tag, "LOCAL")) {
            return joinPath(self.allocator, &.{ self.p_data, "AppData", "Local", folder_name });
        } else if (std.mem.eql(u8, tag, "LOW")) {
            return joinPath(self.allocator, &.{ self.p_data, "AppData", "LocalLow", folder_name });
        } else {
            return joinPath(self.allocator, &.{ self.p_data, "Documents", folder_name });
        }
    }

    fn rootForTag(self: *const Engine, tag: []const u8) ?[]const u8 {
        for (self.sys_roots) |r| {
            if (std.mem.eql(u8, r.tag, tag)) return r.path;
        }
        return null;
    }

    fn setupEnv(self: *const Engine) !void {
        const roam = try joinPath(self.allocator, &.{ self.p_data, "AppData", "Roaming" });
        const local = try joinPath(self.allocator, &.{ self.p_data, "AppData", "Local" });
        const low = try joinPath(self.allocator, &.{ self.p_data, "AppData", "LocalLow" });
        const docs = try joinPath(self.allocator, &.{ self.p_data, "Documents" });

        try ensureDir(roam);
        try ensureDir(local);
        try ensureDir(low);
        try ensureDir(docs);

        try setEnvUtf8(self.allocator, "APPDATA", roam);
        try setEnvUtf8(self.allocator, "LOCALAPPDATA", local);
        try setEnvUtf8(self.allocator, "USERPROFILE", self.p_data);
        try setEnvUtf8(self.allocator, "DOCUMENTS", docs);
    }

    fn snapshotFolders(self: *const Engine) !std.StringHashMap(void) {
        var set = std.StringHashMap(void).init(self.allocator);

        for (self.sys_roots) |r| {
            var dir = std.fs.openDirAbsolute(r.path, .{ .iterate = true }) catch continue;
            defer dir.close();

            var it = dir.iterate();
            while (try it.next()) |entry| {
                if (entry.kind != .directory) continue;

                const key = try std.fmt.allocPrint(
                    self.allocator,
                    "{s}|{s}",
                    .{ r.tag, entry.name },
                );

                try set.put(key, {});
            }
        }

        return set;
    }

    fn snapshotRegistry(self: *const Engine) !std.StringHashMap(void) {
        var set = std.StringHashMap(void).init(self.allocator);

        const output = runCapture(
            self.allocator,
            &.{ "reg", "query", "HKCU\\Software" },
            16 * 1024 * 1024,
        ) catch return set;

        var lines = std.mem.splitScalar(u8, output, '\n');
        while (lines.next()) |raw| {
            const line = std.mem.trim(u8, raw, " \t\r\n");
            if (line.len == 0) continue;

            if (startsWithIgnoreCase(line, "HKEY_CURRENT_USER\\Software\\")) {
                try set.put(try self.allocator.dupe(u8, line), {});
            }
        }

        return set;
    }

    fn clearRegistryBackups(self: *const Engine) !void {
        var dir = std.fs.openDirAbsolute(self.reg_dir, .{ .iterate = true }) catch return;
        defer dir.close();

        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!endsWithIgnoreCase(entry.name, ".reg")) continue;

            const full = try joinPath(self.allocator, &.{ self.reg_dir, entry.name });
            std.fs.cwd().deleteFile(full) catch {};
        }
    }

    fn importRegistryBackups(self: *const Engine) !void {
        var dir = std.fs.openDirAbsolute(self.reg_dir, .{ .iterate = true }) catch return;
        defer dir.close();

        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!endsWithIgnoreCase(entry.name, ".reg")) continue;

            const full = try joinPath(self.allocator, &.{ self.reg_dir, entry.name });
            runWait(self.allocator, &.{ "reg", "import", full }, null, true) catch {};
        }
    }

    fn syncRegistry(self: *const Engine, keys: [][]const u8) !void {
        if (keys.len == 0) return;

        try self.clearRegistryBackups();

        for (keys, 0..) |key, i| {
            const file_name = try std.fmt.allocPrint(self.allocator, "key_{d}.reg", .{i});
            const reg_file = try joinPath(self.allocator, &.{ self.reg_dir, file_name });

            runWait(self.allocator, &.{ "reg", "export", key, reg_file, "/y" }, null, true) catch {};
            runWait(self.allocator, &.{ "reg", "delete", key, "/f" }, null, true) catch {};
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    runWait(allocator, &.{ "cmd", "/c", "chcp", "65001" }, null, true) catch {};

    const engine = try Engine.init(allocator);

    if (pathExists(engine.cfg_file)) {
        const content = std.fs.cwd().readFileAlloc(allocator, engine.cfg_file, 8 * 1024 * 1024) catch null;

        if (content) |json_text| {
            var parsed = std.json.parseFromSlice(
                AppConfig,
                allocator,
                json_text,
                .{
                    .ignore_unknown_fields = true,
                    .allocate = .alloc_always,
                },
            ) catch null;

            if (parsed) |*p| {
                defer p.deinit();
                try runSandbox(&engine, p.value);
                return;
            }
        }
    }

    try learningMode(&engine);
}

fn learningMode(engine: *const Engine) !void {
    var exes = try findCandidateExes(engine.allocator, engine.root);

    if (exes.items.len == 0) {
        focusConsole();
        const out = std.io.getStdOut().writer();
        try out.print("[ERROR] No executable found.\n", .{});
        std.time.sleep(3 * std.time.ns_per_s);
        return;
    }

    try engine.bootstrap();

    const selected_exe = if (exes.items.len == 1) blk: {
        hideConsole();
        break :blk exes.items[0];
    } else blk: {
        focusConsole();
        const idx = try selectOne(engine.allocator, "Select target", exes.items);
        hideConsole();
        break :blk exes.items[idx];
    };

    const reg_before = try engine.snapshotRegistry();
    const folders_before = try engine.snapshotFolders();

    try engine.setupEnv();

    grantFocus();
    hideConsole();

    try runTarget(engine.allocator, engine.root, selected_exe, true);

    std.time.sleep(1 * std.time.ns_per_s);

    const reg_after = try engine.snapshotRegistry();
    const folders_after = try engine.snapshotFolders();

    var reg_candidates = std.ArrayList([]const u8).init(engine.allocator);

    var reg_it = reg_after.iterator();
    while (reg_it.next()) |entry| {
        const key = entry.key_ptr.*;
        if (!reg_before.contains(key) and !containsNoise(key)) {
            try reg_candidates.append(key);
        }
    }

    std.mem.sort([]const u8, reg_candidates.items, {}, stringLessThan);

    var stubborn_candidates = std.ArrayList(StubbornFolder).init(engine.allocator);

    var folder_it = folders_after.iterator();
    while (folder_it.next()) |entry| {
        const key = entry.key_ptr.*;

        if (folders_before.contains(key)) continue;

        const sep = std.mem.indexOfScalar(u8, key, '|') orelse continue;
        const tag = key[0..sep];
        const name = key[sep + 1 ..];

        if (containsNoise(name)) continue;

        try stubborn_candidates.append(.{
            .tag = try engine.allocator.dupe(u8, tag),
            .name = try engine.allocator.dupe(u8, name),
        });
    }

    std.mem.sort(StubbornFolder, stubborn_candidates.items, {}, folderLessThan);

    if (reg_candidates.items.len == 0 and stubborn_candidates.items.len == 0) {
        const empty_config = AppConfig{
            .selected_exe = selected_exe,
            .registry_keys = &.{},
            .stubborn_folders = &.{},
        };

        try saveConfig(engine, empty_config);
        return;
    }

    focusConsole();

    var selected_reg = std.ArrayList([]const u8).init(engine.allocator);

    if (reg_candidates.items.len > 0) {
        const chosen = try selectMany(engine.allocator, "Select registry keys", reg_candidates.items);
        for (chosen.items) |i| {
            try selected_reg.append(reg_candidates.items[i]);
        }
    }

    var selected_folders = std.ArrayList(StubbornFolder).init(engine.allocator);

    if (stubborn_candidates.items.len > 0) {
        var display = std.ArrayList([]const u8).init(engine.allocator);

        for (stubborn_candidates.items) |f| {
            try display.append(try std.fmt.allocPrint(
                engine.allocator,
                "[{s}] {s}",
                .{ f.tag, f.name },
            ));
        }

        const chosen = try selectMany(engine.allocator, "Select folders", display.items);

        for (chosen.items) |i| {
            const f = stubborn_candidates.items[i];

            const root = engine.rootForTag(f.tag) orelse continue;
            const origin = try joinPath(engine.allocator, &.{ root, f.name });
            const dest = try engine.mapPortPath(f.tag, f.name);

            if (std.fs.path.dirname(dest)) |parent| {
                try ensureDir(parent);
            }

            runWait(
                engine.allocator,
                &.{
                    "robocopy",
                    origin,
                    dest,
                    "/E",
                    "/MOVE",
                    "/NFL",
                    "/NDL",
                    "/NJH",
                    "/NJS",
                    "/R:3",
                    "/W:1",
                },
                null,
                true,
            ) catch {};

            try selected_folders.append(f);
        }
    }

    const config = AppConfig{
        .selected_exe = selected_exe,
        .registry_keys = selected_reg.items,
        .stubborn_folders = selected_folders.items,
    };

    try saveConfig(engine, config);
    try engine.syncRegistry(selected_reg.items);
}

fn runSandbox(engine: *const Engine, config: AppConfig) !void {
    try engine.bootstrap();

    if (config.registry_keys.len == 0 and config.stubborn_folders.len == 0) {
        try engine.setupEnv();
        grantFocus();
        try runTarget(engine.allocator, engine.root, config.selected_exe, false);
        return;
    }

    try engine.importRegistryBackups();

    var junctions = std.ArrayList([]const u8).init(engine.allocator);

    for (config.stubborn_folders) |f| {
        const root = engine.rootForTag(f.tag) orelse continue;
        const origin = try joinPath(engine.allocator, &.{ root, f.name });
        const dest = try engine.mapPortPath(f.tag, f.name);

        if (!pathExists(origin) and pathExists(dest)) {
            runWait(
                engine.allocator,
                &.{ "cmd", "/c", "mklink", "/J", origin, dest },
                null,
                true,
            ) catch {};

            if (pathExists(origin)) {
                try junctions.append(origin);
            }
        }
    }

    try engine.setupEnv();

    grantFocus();
    hideConsole();

    try runTarget(engine.allocator, engine.root, config.selected_exe, true);

    for (junctions.items) |j| {
        runWait(engine.allocator, &.{ "cmd", "/c", "rmdir", j }, null, true) catch {};
    }

    try engine.syncRegistry(config.registry_keys);
}

fn saveConfig(engine: *const Engine, config: AppConfig) !void {
    if (std.fs.path.dirname(engine.cfg_file)) |parent| {
        try ensureDir(parent);
    }

    var file = try std.fs.cwd().createFile(engine.cfg_file, .{ .truncate = true });
    defer file.close();

    try std.json.stringify(
        config,
        .{ .whitespace = .indent_4 },
        file.writer(),
    );
}

fn findCandidateExes(
    allocator: std.mem.Allocator,
    root: []const u8,
) !std.ArrayList([]const u8) {
    var list = std.ArrayList([]const u8).init(allocator);

    const self_path = std.fs.selfExePathAlloc(allocator) catch "";
    const self_name = std.fs.path.basename(self_path);

    var dir = try std.fs.openDirAbsolute(root, .{ .iterate = true });
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!endsWithIgnoreCase(entry.name, ".exe")) continue;
        if (std.ascii.eqlIgnoreCase(entry.name, self_name)) continue;

        try list.append(try allocator.dupe(u8, entry.name));
    }

    std.mem.sort([]const u8, list.items, {}, stringLessThan);
    return list;
}

fn runTarget(
    allocator: std.mem.Allocator,
    cwd: []const u8,
    exe_name: []const u8,
    wait: bool,
) !void {
    var child = std.process.Child.init(&.{exe_name}, allocator);
    child.cwd = cwd;

    try child.spawn();

    if (wait) {
        _ = try child.wait();
    }
}

fn runWait(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    cwd: ?[]const u8,
    hide: bool,
) !void {
    var child = std.process.Child.init(argv, allocator);

    child.cwd = cwd;
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    child.windows_hide = hide;

    _ = try child.spawnAndWait();
}

fn runCapture(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    max_output_bytes: usize,
) ![]u8 {
    var child = std.process.Child.init(argv, allocator);

    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;
    child.windows_hide = true;

    try child.spawn();

    const stdout_file = child.stdout.?;
    const output = try stdout_file.reader().readAllAlloc(allocator, max_output_bytes);

    _ = try child.wait();

    return output;
}

fn selectOne(
    allocator: std.mem.Allocator,
    prompt: []const u8,
    items: []const []const u8,
) !usize {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    while (true) {
        try stdout.print("\n{s}\n", .{prompt});

        for (items, 0..) |item, i| {
            try stdout.print("  {d}) {s}\n", .{ i + 1, item });
        }

        try stdout.print("> ", .{});

        const line = try stdin.readUntilDelimiterOrEofAlloc(allocator, '\n', 1024) orelse continue;
        const trimmed = std.mem.trim(u8, line, " \t\r\n");

        const n = std.fmt.parseInt(usize, trimmed, 10) catch continue;

        if (n >= 1 and n <= items.len) {
            return n - 1;
        }
    }
}

fn selectMany(
    allocator: std.mem.Allocator,
    prompt: []const u8,
    items: []const []const u8,
) !std.ArrayList(usize) {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    var result = std.ArrayList(usize).init(allocator);

    if (items.len == 0) return result;

    while (true) {
        try stdout.print("\n{s}\n", .{prompt});

        for (items, 0..) |item, i| {
            try stdout.print("  {d}) {s}\n", .{ i + 1, item });
        }

        try stdout.print("Input numbers separated by comma/space. Empty = none. all = select all.\n> ", .{});

        const line = try stdin.readUntilDelimiterOrEofAlloc(allocator, '\n', 4096) orelse {
            return result;
        };

        const trimmed = std.mem.trim(u8, line, " \t\r\n");

        if (trimmed.len == 0) return result;

        if (std.ascii.eqlIgnoreCase(trimmed, "all")) {
            for (0..items.len) |i| {
                try result.append(i);
            }
            return result;
        }

        var selected = try allocator.alloc(bool, items.len);
        defer allocator.free(selected);
        @memset(selected, false);

        var any_valid = false;
        var tok = std.mem.tokenizeAny(u8, trimmed, ",; \t");

        while (tok.next()) |part| {
            const n = std.fmt.parseInt(usize, part, 10) catch continue;

            if (n >= 1 and n <= items.len) {
                selected[n - 1] = true;
                any_valid = true;
            }
        }

        if (!any_valid) continue;

        for (selected, 0..) |yes, i| {
            if (yes) try result.append(i);
        }

        return result;
    }
}

fn hideConsole() void {
    const hwnd = GetConsoleWindow();
    if (hwnd != null) {
        _ = ShowWindow(hwnd, SW_HIDE);
    }
}

fn focusConsole() void {
    _ = AllocConsole();

    const hwnd = GetConsoleWindow();
    if (hwnd == null) return;

    const foreground_hwnd = GetForegroundWindow();
    const current_thread_id = GetCurrentThreadId();
    const foreground_thread_id = GetWindowThreadProcessId(foreground_hwnd, null);

    var attached = false;

    if (foreground_thread_id != 0 and foreground_thread_id != current_thread_id) {
        attached = AttachThreadInput(foreground_thread_id, current_thread_id, 1) != 0;
    }

    _ = ShowWindow(hwnd, SW_MINIMIZE);
    _ = ShowWindow(hwnd, SW_RESTORE);
    _ = SetForegroundWindow(hwnd);

    if (attached) {
        _ = AttachThreadInput(foreground_thread_id, current_thread_id, 0);
    }
}

fn grantFocus() void {
    _ = AllowSetForegroundWindow(ASFW_ANY);
}

fn setEnvUtf8(
    allocator: std.mem.Allocator,
    name: []const u8,
    value: []const u8,
) !void {
    const name_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, name);
    defer allocator.free(name_w);

    const value_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, value);
    defer allocator.free(value_w);

    if (SetEnvironmentVariableW(name_w.ptr, value_w.ptr) == 0) {
        return error.SetEnvironmentVariableFailed;
    }
}

fn ensureDir(path: []const u8) !void {
    std.fs.cwd().makePath(path) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
}

fn pathExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn joinPath(
    allocator: std.mem.Allocator,
    parts: []const []const u8,
) ![]u8 {
    return std.fs.path.join(allocator, parts);
}

fn containsNoise(s: []const u8) bool {
    for (NOISE_KEYWORDS) |needle| {
        if (containsIgnoreCase(s, needle)) return true;
    }
    return false;
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;

    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (eqlIgnoreCaseAscii(haystack[i .. i + needle.len], needle)) {
            return true;
        }
    }

    return false;
}

fn startsWithIgnoreCase(s: []const u8, prefix: []const u8) bool {
    if (s.len < prefix.len) return false;
    return eqlIgnoreCaseAscii(s[0..prefix.len], prefix);
}

fn endsWithIgnoreCase(s: []const u8, suffix: []const u8) bool {
    if (s.len < suffix.len) return false;
    return eqlIgnoreCaseAscii(s[s.len - suffix.len ..], suffix);
}

fn eqlIgnoreCaseAscii(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;

    for (a, b) |ca, cb| {
        if (std.ascii.toLower(ca) != std.ascii.toLower(cb)) return false;
    }

    return true;
}

fn stringLessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

fn folderLessThan(_: void, a: StubbornFolder, b: StubbornFolder) bool {
    const tag_order = std.mem.order(u8, a.tag, b.tag);

    if (tag_order == .eq) {
        return std.mem.lessThan(u8, a.name, b.name);
    }

    return tag_order == .lt;
}