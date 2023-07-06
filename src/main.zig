const std = @import("std");
const builtin = @import("builtin");
const http = std.http;
const fs = std.fs;
const json = std.json;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Client = std.http.Client;
const ComptimeStringMap = std.ComptimeStringMap;
const Parsed = json.Parsed;
const Scanner = json.Scanner;
const SourceLocation = std.builtin.SourceLocation;
const StringArrayList = std.ArrayList([]const u8);
const StringHashMap = std.StringHashMap;
const assert = std.debug.assert;
const stringToEnum = std.meta.stringToEnum;

fn todo(msg: []const u8, src: SourceLocation) void {
    std.log.warn("TODO {s}:{d}:{d} \"{s}\"", .{ src.file, src.line, src.column, msg });
}

/// Simple wrapper around the mem eql function
/// ```zig
/// const assert = std.debug.assert;
///
/// var string_a = "hello, ";
/// var string_b = "world!";
/// var string_c = "hello, ";
/// assert(!strcmp(string_a, string_b));
/// assert(strcmp(string_a, string_c));
/// ```
fn strcmp(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

/// Caller owns returned memory, must be freed
/// ```zig
/// var string_a = "Hello, ";
/// var string_b = "World!";
/// // Whatever allocator used doesn't matter. Just use the same one to free.
/// var string_c = try concat(allocator, &[_][]const u8{string_a, string_b});
/// defer allocator.free(string_c);
/// // string_c = "Hello, World!"
/// ```
fn concat(allocator: Allocator, items: []const []const u8) ![]const u8 {
    return try std.mem.concat(allocator, u8, items);
}

/// Takes an absolute path and creates it if it doesn't exist
/// Fails on a non-absolute path, doesn't fail if the path already exists.
fn createDirectoryIfNotExists(path: []const u8) !void {
    // Throws an error if not found
    fs.accessAbsolute(path, .{}) catch {
        try fs.makeDirAbsolute(path);
    };
}

/// Takes an absolute path and creates it if it doesn't exist
/// Fails on a non-absolute path, doesn't fail if the path already exists.
fn createFileIfNotExists(path: []const u8) !void {
    fs.accessAbsolute(path, .{}) catch {
        (try fs.createFileAbsolute(path, .{})).close();
    };
}

/// The Available Commands for the program
/// To be used in conjunction with the `ArgParser` struct
/// To be able to switch on Commands
pub const Command = enum {
    list,
    install,
    select,
    delete,
};

pub const Flags = struct {
    const AliasMap = ComptimeStringMap([]const u8, .{
        .{ "-i", "list_installed" },
        .{ "--list-installed", "list_installed" },
        .{ "-rc", "reload_cache" },
        .{ "--reload-cache", "reload_cache" },
    });

    list_installed: bool = false,
    reload_cache: bool = false,

    /// Toggles the named flag in the existing instance of the Flags struct
    pub fn toggleFlag(self: *Flags, flag_name: []const u8) void {
        inline for (@typeInfo(Flags).Struct.fields) |field| {
            if (AliasMap.get(flag_name)) |flag| {
                if (strcmp(flag, field.name)) {
                    @field(self, field.name) = !@field(self, field.name);
                }
            }
        }
    }

    pub fn isFlag(flag_name: []const u8) bool {
        inline for (@typeInfo(Flags).Struct.fields) |field| {
            if (AliasMap.get(flag_name)) |flag| {
                if (strcmp(flag, field.name)) {
                    return true;
                }
            }
        }
        return false;
    }
};

/// Parses the Command Line Arguments into the struct, populating the `selected` field with the first matching command
/// Also parses the Flags into the given struct, allowing the user to easily use the flags in an if statement
pub fn ArgParser(comptime TCommand: type, comptime TFlag: type) type {
    comptime if (!@hasDecl(TFlag, "toggleFlag"))
        @compileError("`TFlags` Missing the `toggleFlag` function");

    return struct {
        const Self = @This();

        selected: ?TCommand,
        flags: TFlag,
        args: [][]const u8,

        pub fn init(allocator: Allocator, args: [][]const u8) !Self {
            var selected: ?TCommand = null;
            var flags = TFlag{};
            var arguments = StringArrayList.init(allocator);
            errdefer arguments.deinit();

            for (args) |arg| {
                if (selected == null) {
                    if (stringToEnum(TCommand, arg)) |cmd| {
                        selected = cmd;
                    } else return error.InvalidCommandError;

                    continue;
                }

                if (Flags.isFlag(arg)) {
                    flags.toggleFlag(arg);
                } else {
                    try args.append(arg);
                }
            }

            return Self{
                .selected = selected,
                .flags = flags,
                .args = try arguments.toOwnedSlice(),
            };
        }
    };
}

pub fn getComputerArchitecture() ![]const u8 {
    const archictecture = switch (builtin.cpu.arch) {
        .x86_64 => "x86_64",
        else => return error.UnsupportedArchitecture,
    };

    const os = switch (builtin.os.tag) {
        .windows => "windows",
        else => return error.UnsupportedOperatingSystem,
    };

    return archictecture ++ "-" ++ os;
}

pub const Download = struct {
    tarball: ?[]const u8 = null,
    shasum: ?[]const u8 = null,
    size: ?[]const u8 = null,
};

pub const DownloadPair = struct { name: []const u8, download: Download };
pub const DownloadPairList = ArrayList(DownloadPair);

pub const Version = struct {
    version: ?[]const u8 = null,
    date: ?[]const u8 = null,
    docs: ?[]const u8 = null,
    downloads: DownloadPairList,

    pub fn deinit(self: *Version) void {
        self.downloads.deinit();
    }
};

pub const VersionPair = struct { name: []const u8, version: Version };
pub const VersionPairList = ArrayList(VersionPair);

pub const VersionParser = struct {
    allocator: Allocator,
    scanner: Scanner,

    pub fn init(allocator: Allocator, index: []const u8) VersionParser {
        var scanner = Scanner.initCompleteInput(allocator, index);

        return VersionParser{
            .allocator = allocator,
            .scanner = scanner,
        };
    }

    pub fn deinit(self: *VersionParser) void {
        self.scanner.deinit();
    }

    pub fn parse(self: *VersionParser) !VersionPairList {
        var result = VersionPairList.init(self.allocator);

        var token = try self.scanner.next();

        while (token != .end_of_document) : (token = try self.scanner.next()) {
            switch (token) {
                .string => |str| {
                    if ((try self.scanner.peekNextTokenType()) == .object_begin) {
                        _ = try self.scanner.next(); // Skip the object opening
                        try self.parseVersion(str, &result);
                        continue;
                    }
                },
                else => todo("Unhandled Switch Cases", @src()),
            }
        }

        return result;
    }

    pub fn parseVersion(self: *VersionParser, name: []const u8, parent_list: *VersionPairList) !void {
        var version = Version{
            .downloads = DownloadPairList.init(self.allocator),
        };

        var token = try self.scanner.next();

        while (token != .object_end) : (token = try self.scanner.next()) {
            switch (token) {
                .string => |str| {
                    if ((try self.scanner.peekNextTokenType()) == .object_begin) {
                        _ = try self.scanner.next(); // Skip the object opening
                        try self.parseDownload(str, &version.downloads);
                        continue;
                    }

                    inline for (@typeInfo(Version).Struct.fields) |field| {
                        if (field.type != ?[]const u8) continue;
                        if (strcmp(str, field.name)) {
                            @field(version, field.name) = (try self.scanner.next()).string; // This will fail if the value is not a string

                        }
                    }
                },
                else => todo("Unhandled Switch Cases", @src()),
            }
        }

        try parent_list.append(VersionPair{ .name = name, .version = version });
    }

    pub fn parseDownload(self: *VersionParser, name: []const u8, parent_list: *DownloadPairList) !void {
        var download = Download{};

        var token = try self.scanner.next();

        while (token != .object_end) : (token = try self.scanner.next()) {
            switch (token) {
                .string => |str| {
                    inline for (@typeInfo(Download).Struct.fields) |field| {
                        if (strcmp(str, field.name)) {
                            @field(download, field.name) = (try self.scanner.next()).string; // This will fail if the value is not a string
                        }
                    }
                },
                else => todo("Unhandled Switch Cases", @src()),
            }
        }

        try parent_list.append(DownloadPair{ .name = name, .download = download });
    }
};

pub const HttpClient = struct {
    const MAX_RETRIES = 5;
    const INDEX_URL = "https://ziglang.org/download/index.json";

    allocator: Allocator,
    client: Client,

    pub fn init(allocator: Allocator) HttpClient {
        return .{
            .allocator = allocator,
            .client = Client{ .allocator = allocator },
        };
    }

    pub fn deinit(self: *HttpClient) void {
        self.client.deinit();
    }

    pub fn get(self: *HttpClient, url: []const u8) ![]const u8 {
        var uri = try std.Uri.parse(url);

        var current_retries: u8 = 0;

        var request: Client.Request = request_blk: while (current_retries < MAX_RETRIES) : (current_retries += 1) {
            var res = self.client.request(.GET, uri, .{ .allocator = self.allocator }, .{}) catch |err| {
                std.log.err("Request {} Failed: {!}", .{ current_retries, err });
                continue;
            };
            break :request_blk res;
        } else {
            return error.RequestFailedError;
        };
        defer request.deinit();

        if (current_retries >= MAX_RETRIES) {
            std.log.err("Retry Attempt exceed Maximum Retries {}", .{MAX_RETRIES});
            return error.DownloadError;
        }

        request.start() catch |err| {
            std.log.err("Error Starting the request {!}", .{err});
            return err;
        };

        request.wait() catch |err| {
            std.log.err("Error Waiting the request {!}", .{err});
            return err;
        };

        request.finish() catch |err| {
            std.log.err("Error Finishing the request {!}", .{err});
            return err;
        };

        if (request.response.status.class() != .success) {
            std.log.err("Request Failed {s}", .{request.response.reason});
            return error.UnsuccessfulStatusCode;
        }

        var reader = request.reader();

        var contents = try reader.readAllAlloc(self.allocator, request.response.content_length orelse (100 * 1024 * 1024));

        return contents;
    }
};

pub const FileSystem = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) FileSystem {
        return FileSystem{ .allocator = allocator };
    }

    /// Sets up the file system to house the Zig Versions
    pub fn setup(self: *FileSystem) !void {
        var root = try self.getAppDataDir();
        defer self.allocator.free(root);
        try createDirectoryIfNotExists(root);

        // Required items are:
        // "versions" (dir) -> where the actual versions are stored
        var versions_path = try concat(self.allocator, &[_][]const u8{ root, "/versions" });
        defer self.allocator.free(versions_path);
        try createDirectoryIfNotExists(versions_path);

        // "version.install" (dir) -> where the version is installed before decompression
        var version_install_path = try concat(self.allocator, &[_][]const u8{ root, "/version.install" });
        defer self.allocator.free(version_install_path);
        try createDirectoryIfNotExists(version_install_path);

        // "zig" (dir / symlink) -> the location added to path, sym links to current selected version
        var zig_path = try concat(self.allocator, &[_][]const u8{ root, "/zig" });
        defer self.allocator.free(zig_path);
        try createDirectoryIfNotExists(zig_path);

        // "config.json" (file) -> the configuration, outlined by the Config struct
        var config_path = try concat(self.allocator, &[_][]const u8{ root, "/config.json" });
        defer self.allocator.free(config_path);
        try createFileIfNotExists(config_path);

        // "cache.json" (file) -> the cache, outlined by the Cache struct
        var cache_path = try concat(self.allocator, &[_][]const u8{ root, "/cache.json" });
        defer self.allocator.free(cache_path);
        try createFileIfNotExists(cache_path);
    }

    pub fn getAppDataDir(self: *FileSystem) ![]const u8 {
        return try std.fs.getAppDataDir(self.allocator, "zvm");
    }

    pub fn getConfigPath(self: *FileSystem) ![]const u8 {
        var root = try self.getAppDataDir();
        defer self.allocator.free(root);
        return try concat(
            self.allocator,
            &[_][]const u8{ root, "/config.json" },
        );
    }
};

/// Loads the contents of the given file path, caller owns returned memory
/// Form the App Data Dir of the user, e.g.
fn loadFileContents(allocator: Allocator, path: []const u8) ![]const u8 {
    var file_system = FileSystem.init(allocator);
    var root = try file_system.getAppDataDir();
    defer allocator.free(root);
    var file_path = try concat(allocator, &[_][]const u8{ root, "/", path });
    var file = try fs.openFileAbsolute(file_path, .{});
    defer file.close();

    return try file.reader().readAllAlloc(allocator, 1028);
}

pub const Config = struct {
    selected: []const u8,

    /// Setup will initialise the `config.json` file
    /// It will load the config file with the defaults for each setting
    pub fn setup(_: Allocator) !void {
        todo("Config.setup not implemented.", @src());
    }

    /// Loads the Config from users config directory /config.json
    /// Caller owns the `Parsed(Config)` and must call `deinit` on it
    /// ```zig
    /// var allocator = std.heap.page_allocator;
    /// var config = try Config.loadFromFile(allocator);
    /// defer config.deinit();
    /// var conf = config.value;  // Optional, can just do config.value everywhere
    /// ```
    pub fn loadFromFile(allocator: Allocator) !Parsed(Config) {
        var config_contents = try loadFileContents(allocator, "config.json");
        if (!(try json.validate(allocator, config_contents))) {}
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    // var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    // defer arena.deinit();
    // var allocator = arena.allocator();
    var allocator = gpa.allocator();

    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var arg_parser = try ArgParser(Command, Flags).init(allocator, args[1..]);
    std.log.info("{any}", .{arg_parser});

    var file_system = FileSystem.init(allocator);
    try file_system.setup();

    var config = try Config.loadFromFile(allocator);
    _ = config;
    // defer config.deinit();
    // std.log.info("{any}", .{config.value});

    // var http_client = HttpClient.init(allocator);
    // defer http_client.deinit();

    // var zig_index = try http_client.get(HttpClient.INDEX_URL);
    // defer allocator.free(zig_index);

    // var index = try std.fs.cwd().openFile("./index.json", .{ .mode = .read_only });
    // defer index.close();
    // var zig_index = try index.reader().readAllAlloc(allocator, 100_000);
    // defer allocator.free(zig_index);

    // var parser = VersionParser.init(allocator, zig_index);
    // defer parser.deinit();

    // var version_list = try parser.parse();
    // defer {
    //     for (version_list.items) |item| {
    //         var version = item.version;
    //         version.deinit();
    //     }

    //     version_list.deinit();
    // }

}
