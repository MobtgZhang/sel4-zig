//! Boot-image format dispatch. Filesystem rules stay independent of CPU and UEFI.
const std = @import("std");
const archive = @import("ramfs.zig");
const ext = @import("ext.zig");
const fat = @import("fat.zig");
const ntfs = @import("ntfs.zig");

pub const FileSystem = union(enum) {
    archive: archive.FileSystem,
    ext: ext.FileSystem,
    fat: fat.FileSystem,
    ntfs: ntfs.FileSystem,

    pub fn mount(bytes: []const u8) !FileSystem {
        if (bytes.len >= 512 and std.mem.eql(u8, bytes[3..11], "NTFS    ")) return .{ .ntfs = try ntfs.FileSystem.mount(bytes) };
        if (bytes.len >= 1082 and std.mem.readInt(u16, bytes[1080..1082], .little) == 0xef53) {
            return .{ .ext = try ext.FileSystem.mount(bytes) };
        }
        if (bytes.len >= 512 and (bytes[0] == 0xeb or bytes[0] == 0xe9) and std.mem.readInt(u16, bytes[510..512], .little) == 0xaa55) return .{ .fat = try fat.FileSystem.mount(bytes) };
        return .{ .archive = try archive.FileSystem.mount(bytes) };
    }
    pub fn read(self: *const FileSystem, path: []const u8) ![]const u8 {
        return switch (self.*) {
            .archive => |*fs| fs.read(path),
            .ext => |*fs| fs.read(path),
            .fat => |*fs| fs.read(path),
            .ntfs => |*fs| fs.read(path),
        };
    }
    pub fn list(self: *const FileSystem, path: []const u8, writer: anytype) !void {
        switch (self.*) {
            .archive => |*fs| try fs.list(path, writer),
            .ext => |*fs| try fs.list(path, writer),
            .fat => |*fs| try fs.list(path, writer),
            .ntfs => |*fs| try fs.list(path, writer),
        }
    }
    pub fn name(self: *const FileSystem) []const u8 {
        return switch (self.*) {
            .archive => "USTAR",
            .ext => |*fs| if (fs.bytes[1120] & 0x40 != 0) "EXT4" else if (fs.bytes[1116] & 4 != 0) "EXT3" else "EXT2",
            .fat => |*fs| if (fs.fat32) "FAT32" else "FAT16",
            .ntfs => "NTFS",
        };
    }
    pub fn fileSize(self: *const FileSystem, path: []const u8) !u64 {
        return switch (self.*) {
            .archive => |*fs| (try fs.read(path)).len,
            .ext => |*fs| (try fs.open(path)).size,
            .fat => |*fs| (try fs.open(path)).size,
            .ntfs => |*fs| (try fs.open(path)).size,
        };
    }
    /// Copy reads support fragmented and sparse files without exposing disk layout.
    pub fn readAt(self: *const FileSystem, path: []const u8, offset: u64, output: []u8) !usize {
        return switch (self.*) {
            .archive => |*fs| fs.readAt(path, offset, output),
            .ext => |*fs| fs.readAt(try fs.open(path), offset, output),
            .fat => |*fs| fs.readAt(try fs.open(path), offset, output),
            .ntfs => |*fs| fs.readAt(try fs.open(path), offset, output),
        };
    }
};
