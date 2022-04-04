const std = @import("std");
const testing = std.testing;

pub fn RGBLink(
    comptime N: usize,
) type {
    return struct {
        const Self = @This();
        pub const Color = std.math.IntFittingRange(0, N);

        color: Color = 0,
        left: ?*Self = null,
        right: ?*Self = null,
        parent: ?*Self = null,
    };
}

pub fn RGBTree(
    comptime Context: type,
) type {
    return struct {
        const Self = @This();
        const Link = @TypeOf(@field(@as(Node, undefined), link_field));
        const Key = Context.Key;
        const Node = Context.Node;
        const link_field = Context.link_field;

        root: ?*Link = null,

        pub fn insert(self: *Self, ctx: Context, node: *Node) void {
            if (self.root) |root| {
                self.insertInto(ctx, root, node);
            } else {
                self.root = &@field(node, link_field);
            }
        }

        fn insertInto(self: *Self, ctx: Context, link: *Link, node: *Node) void {
            const other_link = &@field(node, link_field);
            const link_key = ctx.getKey(@fieldParentPtr(Node, link_field, link));
            const node_key = ctx.getKey(node);
            if (ctx.lessThan(node_key, link_key)) {
                if (link.left) |left| {
                    self.insertInto(ctx, left, node);
                } else {
                    link.left = other_link;
                    other_link.parent = link;
                }
            } else {
                if (link.right) |right| {
                    self.insertInto(ctx, right, node);
                } else {
                    link.right = other_link;
                    other_link.parent = link;
                }
            }
        }

        pub fn find(self: *Self, ctx: Context, key: Key) ?*Node {
            if (self.root) |root| {
                return self.findIn(ctx, root, key);
            } else {
                return null;
            }
        }

        fn findIn(self: *Self, ctx: Context, link: *Link, key: Key) ?*Node {
            const node = @fieldParentPtr(Node, link_field, link);
            const link_key = ctx.getKey(node);

            if (ctx.lessThan(key, link_key)) {
                if (link.left) |left| {
                    return self.findIn(ctx, left, key);
                } else {
                    return null;
                }
            } else if (ctx.lessThan(link_key, key)) {
                if (link.right) |right| {
                    return self.findIn(ctx, right, key);
                } else {
                    return null;
                }
            } else {
                return node;
            }
        }
    };
}

const TestNode = struct {
    val: usize,
    link: RGBLink(1) = .{},
};

const NodeContext = struct {
    pub const Key = usize;
    pub const Node = TestNode;
    pub const link_field = "link";

    pub fn getKey(_: NodeContext, node: *Node) usize {
        return node.val;
    }

    pub fn lessThan(_: NodeContext, left: Key, right: Key) bool {
        return left < right;
    }
};

test "basic functionality" {
    var tree = RGBTree(NodeContext){};

    var a = TestNode{ .val = 1 };
    var b = TestNode{ .val = 3 };
    var c = TestNode{ .val = 5 };

    tree.insert(.{}, &a);
    tree.insert(.{}, &b);
    tree.insert(.{}, &c);

    try testing.expectEqual(@as(?*TestNode, &a), tree.find(.{}, 1));
    try testing.expectEqual(@as(?*TestNode, &b), tree.find(.{}, 3));
    try testing.expectEqual(@as(?*TestNode, &c), tree.find(.{}, 5));

    try testing.expectEqual(@as(?*TestNode, null), tree.find(.{}, 0));
    try testing.expectEqual(@as(?*TestNode, null), tree.find(.{}, 2));
    try testing.expectEqual(@as(?*TestNode, null), tree.find(.{}, 4));
    try testing.expectEqual(@as(?*TestNode, null), tree.find(.{}, 6));
}
