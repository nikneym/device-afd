const std = @import("std");
const os = std.os;
const posix = std.posix;
const windows = os.windows;
const ntdll = windows.ntdll;
const assert = std.debug.assert;

pub const AFD_POLL_HANDLE_INFO = extern struct {
    Handle: windows.HANDLE,
    Events: windows.ULONG,
    Status: windows.NTSTATUS,
};

pub const AFD_POLL_INFO = extern struct {
    Timeout: windows.LARGE_INTEGER,
    NumberOfHandles: windows.ULONG,
    Exclusive: windows.ULONG,
    // followed by an array of `NumberOfHandles` AFD_POLL_HANDLE_INFO
    // Handles[]: AFD_POLL_HANDLE_INFO,
};

pub fn main() !void {
    _ = try windows.WSAStartup(2, 2);
    defer windows.WSACleanup() catch unreachable;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var handle: windows.HANDLE = windows.INVALID_HANDLE_VALUE;

    // Device name can be anything; it just has to be under `\Device\Afd`.
    const device_name = try std.unicode.utf8ToUtf16LeAlloc(allocator, "\\Device\\Afd\\beelzebub");
    defer allocator.free(device_name);

    var object_name = windows.UNICODE_STRING{
        .Length = @intCast(device_name.len * @sizeOf(u16)),
        .MaximumLength = @intCast(device_name.len * @sizeOf(u16)),
        .Buffer = device_name.ptr,
    };

    var attributes = windows.OBJECT_ATTRIBUTES{
        .Length = @sizeOf(windows.OBJECT_ATTRIBUTES),
        .RootDirectory = null,
        .ObjectName = &object_name,
        .Attributes = 0,
        .SecurityDescriptor = null,
        .SecurityQualityOfService = null,
    };

    var status_block: windows.IO_STATUS_BLOCK = undefined;

    // Opening an afd device.
    const res = ntdll.NtCreateFile(
        &handle,
        windows.SYNCHRONIZE,
        &attributes,
        &status_block,
        null,
        0,
        windows.FILE_SHARE_READ | windows.FILE_SHARE_WRITE,
        windows.FILE_OPEN,
        0,
        null,
        0,
    );
    assert(res == .SUCCESS);

    const socket = try posix.socket(posix.AF.INET, posix.SOCK.STREAM | posix.SOCK.NONBLOCK | posix.SOCK.CLOEXEC, posix.IPPROTO.TCP);
    defer posix.close(socket);

    const addr = try std.net.Address.parseIp("142.250.184.142", 80);
    posix.connect(socket, &addr.any, addr.getOsSockLen()) catch |err| switch (err) {
        error.WouldBlock => {},
        else => return err,
    };

    // Get the base handle of a socket. This is needed when working with afd.
    var bytes_returned: u32 = 0;
    var base_socket: windows.ws2_32.SOCKET = windows.ws2_32.INVALID_SOCKET;
    const rc = windows.ws2_32.WSAIoctl(
        socket,
        windows.ws2_32.SIO_BASE_HANDLE,
        null,
        0,
        @ptrCast(&base_socket),
        @sizeOf(windows.ws2_32.SOCKET),
        &bytes_returned,
        null,
        null,
    );
    assert(rc == 0);

    var ioctl_data: extern struct {
        afd_poll_info: AFD_POLL_INFO,
        handles: [1]AFD_POLL_HANDLE_INFO,
    } = .{
        .afd_poll_info = .{
            .Timeout = std.math.maxInt(i64),
            .NumberOfHandles = 1,
            .Exclusive = 0,
        },
        .handles = .{
            .{ .Handle = base_socket, .Status = .SUCCESS, .Events = AFD_POLL_SEND },
        },
    };

    var io_status_block: windows.IO_STATUS_BLOCK = undefined;
    var overlapped = std.mem.zeroes(windows.OVERLAPPED);
    // Block until we've connected.
    while (true) {
        const rc1 = ntdll.NtDeviceIoControlFile(handle, null, null, &overlapped, &io_status_block, IOCTL_AFD_POLL, &ioctl_data, @sizeOf(@TypeOf(ioctl_data)), &ioctl_data, @sizeOf(@TypeOf(ioctl_data)));
        std.debug.print("{}\n", .{rc1});

        if (rc1 == .SUCCESS) {
            break;
        }
    }
}

pub const IOCTL_AFD_POLL = 0x00012024;

pub const AFD_POLL_RECEIVE_BIT = 0;
pub const AFD_POLL_RECEIVE = 1 << AFD_POLL_RECEIVE_BIT;
pub const AFD_POLL_RECEIVE_EXPEDITED_BIT = 1;
pub const AFD_POLL_RECEIVE_EXPEDITED = 1 << AFD_POLL_RECEIVE_EXPEDITED_BIT;
pub const AFD_POLL_SEND_BIT = 2;
pub const AFD_POLL_SEND = 1 << AFD_POLL_SEND_BIT;
pub const AFD_POLL_DISCONNECT_BIT = 3;
pub const AFD_POLL_DISCONNECT = 1 << AFD_POLL_DISCONNECT_BIT;
pub const AFD_POLL_ABORT_BIT = 4;
pub const AFD_POLL_ABORT = 1 << AFD_POLL_ABORT_BIT;
pub const AFD_POLL_LOCAL_CLOSE_BIT = 5;
pub const AFD_POLL_LOCAL_CLOSE = 1 << AFD_POLL_LOCAL_CLOSE_BIT;
pub const AFD_POLL_CONNECT_BIT = 6;
pub const AFD_POLL_CONNECT = 1 << AFD_POLL_CONNECT_BIT;
pub const AFD_POLL_ACCEPT_BIT = 7;
pub const AFD_POLL_ACCEPT = 1 << AFD_POLL_ACCEPT_BIT;
pub const AFD_POLL_CONNECT_FAIL_BIT = 8;
pub const AFD_POLL_CONNECT_FAIL = 1 << AFD_POLL_CONNECT_FAIL_BIT;
pub const AFD_POLL_QOS_BIT = 9;
pub const AFD_POLL_QOS = 1 << AFD_POLL_QOS_BIT;
pub const AFD_POLL_GROUP_QOS_BIT = 10;
pub const AFD_POLL_GROUP_QOS = 1 << AFD_POLL_GROUP_QOS_BIT;
