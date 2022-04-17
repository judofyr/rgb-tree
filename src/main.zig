const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;
const Order = std.math.Order;

// Alright, lets dive straigth into the complicated logic here.
// Modifications of an RGB tree first happens naively (insert/remove)
// the node at the "obvious" place, and later we try to repair any
// invariants which we've broken. There's two repair methods:
//
// - Repairing color violation: This can happen after insertion.
// - Repairing zero imbalance: This can happen after removal.

// ## Repair color violation
//
// During insertion we might end up in a situation where a node has
// the same (non-zero) color as its child:
//
//    3
//   / \
//  3   x
//
// There's three different strategies:
// 1. We can increase our color [only valid if we've not reached N].
// 2. Our parent is a 0-colored node which we can "push" down.
// 3. We can rotate.
//
// Number 1 is trivial so let's instead look at number 2:
//
//      0
//     / \
//    3   2
//   / \
//  3   x
//
// In this case we can "push" the 0 down and re-color the parent as non-zero:
//
//      ?
//     / \
//    0   0
//   / \
//  3   x
//
// The re-coloring of the parent might cause a new color violation and thus we might need to recurse.
//
// Next let's look at what happens during a rotation:
//
//     ?
//    / \
//   2   a
//  / \
// 2   b
//
// Rotating (+ recoloring) this will lead to this tree:
//
//    ?
//   / \
//  2   2
//     / \
//    b   a
//
//
// Notice that `a` was now moved beneath the first link. As long as we know that
// this node has a color that's smaller than our color (or it's 0-colored) then
// we can safely rotate and this will solve our violation.
//
// In should also be mentioned that if the color violation is the "other" way
// we need to do something a bit differently:
//
//    (3)
//    / \
//  [2]  a
//  / \
// b   2
//
// In this case we need to first rotate around [2]:
//
//      (3)
//      / \
//     2   a
//    /
//   2
//  /
// b
//
// And then rotate around the parent:
//
//     3
//    / \
//   2   2
//  /     \
// b       a
//
// And once again we see that both `a` and `b` become children.

// ## Repair zero imbalance
// For deletion we require that at least one of the child pointers are null.
// This makes it trivial to delete the node (just replace its link with the child),
// but we need to take care to maintain the invariants.
//
// There are two trivial cases:
// (1) If the removed node has color>0, then there's nothing to do.
// (2) If the removed node has color=0, but it has a child with color>0,
//     then we can re-label the child as color=0 and everything is good.
//
// The third case looks like this:
//
//      x
//     / \
//   (0)   y
//   /
//  0
//
// Here `(0)` is is the node we want to remove. It has one child also with color=0.
// We first remove it and end up with this tree:
//
//   x
//  / \
// 0   y
//
// (It's also possible for this child node to exist at all. This leads to the same scenario.)
//
// This is now no longer valid since originally we had two zero-colored node in the path,
// and we knew that it was in balance with the other part. Now we've removed one so
// we're missing one 0-colored node. We therefore need to somehow try to sneak in
// another 0-colored node.
//
// We'll just have to go through all the different cases and resolve them one by one.
//
// For this section we use these identifiers:
// - `x` is any node.
// - `k` is a node with color > 0.
// - `m` is a node with color < n - 1.
//
// Note that even if the same identifier appears twice they don't neccesarily represent the same color.
//
// Case 1:
//
//    x
//   / \
//  0  (0)
//     / \
//    m   m
//
// => [re-color]
//
//    x
//   / \
//  0   n
//     / \
//    m   m
//
// The first case is the simplest: We can convert the (0) node into color `n` (maximum color).
// This is only allowed if it doesn't have any children with color=n. The effect of this
// is that the two siblings are now balanced in terms of 0-colored nodes. However,
// the parent is now unbalanced with respect to _its_ sibling. If the parent is
// non-zero colored we can just flip it. Otherwise we'll have to recurse up.
//
// Case 2a:
//
//   x
//  / \
// 0   0
//    / \
//   x   k
//
// => [rotate left + re-color as 0]
//
//     x
//    / \
//   0   0
//  / \
// 0   x
//
// The second case happens when the sibling has a non-zero child.
// The trick here is that by rotating + converting it to a zero-colored node
// We keep the same 0-count on the right, but increase it on the left.
//
// Case 2b:
//
//   x
//  / \
// 0   0
//    / \
//   k   x
//
// This is a variant of the previous one, but `x` and `k` are flipped. This will
// also be resolved with a rotation, but we need the "double" rotation
// like we do during "repair color violation".
//
// Case 3:
//
//   x
//  / \
// 0   k
//    / \
//   x   x
//
// => [rotate]
//
//     x
//    / \
//   k   x
//  / \
// 0   x
//
// => then recurse at the _same_ node.
//
// This is neat: This transformation is certainly valid, but it doesn't
// seem to resolve any imbalances. How does it work? The trick here is that
// it "pulls" up nodes from the right-hand side. Due to the decreasing colors
// _eventually_ this will pull up a node with color=0. And then we're back
// into the two other cases.

const Dir = enum {
    left,
    right,

    fn inverse(self: Dir) Dir {
        return if (self == .left) .right else .left;
    }
};

pub fn Link(
    comptime N: usize,
) type {
    return struct {
        const Self = @This();
        pub const Color = std.math.IntFittingRange(0, N);
        pub const N = N;

        color: Color = 0,
        children: [2]?*Self = .{ null, null },
        parent: ?*Self = null,

        pub fn getChild(self: Self, dir: Dir) ?*Self {
            return self.children[@enumToInt(dir)];
        }

        // dirOf returns the direction of a child.
        fn dirOf(self: Self, child: *Self) Dir {
            if (self.children[0] == child) {
                return .left;
            } else if (self.children[1] == child) {
                return .right;
            } else {
                unreachable;
            }
        }

        fn setChild(self: *Self, dir: Dir, child: ?*Self) void {
            self.children[@enumToInt(dir)] = child;
            if (child) |c| {
                c.parent = self;
            }
        }
    };
}

pub fn Tree(
    comptime N: usize,
    comptime Key: type,
    comptime getKey: fn (link: *const Link(N)) Key,
    comptime compare: fn (lhs: anytype, rhs: anytype) Order,
) type {
    return struct {
        const Self = @This();
        const LinkType = Link(N);

        root: ?*LinkType = null,

        pub fn init() Self {
            return Self{};
        }

        // Validation

        pub fn validate(self: *const Self) !void {
            if (self.root) |root_link| {
                if (root_link.parent != null) return error.Invalid;
                _ = try self.validateLink(root_link);
            }
        }

        fn validateLink(self: *const Self, link: *const LinkType) error{ InvalidParent, InvalidDecrease, InvalidBalance, InvalidOrder }!usize {
            _ = self;

            const key = getKey(link);

            if (link.getChild(.left)) |left_child| {
                const left_key = getKey(left_child);
                if (compare(key, left_key) == Order.lt) {
                    return error.InvalidOrder;
                }
            }

            if (link.getChild(.right)) |right_child| {
                const right_key = getKey(right_child);
                if (compare(key, right_key) == Order.gt) {
                    return error.InvalidOrder;
                }
            }

            var heights: [2]usize = .{ 0, 0 };

            for (link.children) |child, idx| {
                if (child) |child_link| {
                    if (child_link.parent != link) return error.InvalidParent;

                    if (link.color > 0 and child_link.color >= link.color) {
                        return error.InvalidDecrease;
                    }

                    var child_count = try self.validateLink(child_link);
                    heights[idx] = child_count;
                }
            }

            if (heights[0] != heights[1]) return error.InvalidBalance;

            if (link.color == 0) {
                return heights[0] + 1;
            } else {
                return heights[0];
            }
        }

        // Entrypoints to the public API
        pub fn find(self: *Self, key: Key) ?*LinkType {
            if (self.root) |root| {
                return self.findIn(root, key);
            } else {
                return null;
            }
        }

        pub fn insert(self: *Self, link: *LinkType) void {
            if (self.root) |root| {
                const key = getKey(link);
                self.insertInto(root, link, key);
            } else {
                self.root = link;
            }
        }

        pub fn remove(self: *Self, link: *LinkType) void {
            var left_link = link.getChild(.left);
            var right_link = link.getChild(.right);

            if (left_link == null) {
                self.removeLink(link, .left);
            } else if (right_link == null) {
                self.removeLink(link, .right);
            } else {
                var succ = self.firstOf(right_link.?);
                self.removeLink(succ, .left);
                self.replaceLink(link, succ);
            }
        }

        pub fn first(self: *Self) ?*LinkType {
            if (self.root) |link| {
                return self.firstOf(link);
            }
            return null;
        }

        pub fn next(self: *Self, link: *LinkType) ?*LinkType {
            var curr = link;
            if (curr.getChild(.right)) |right_link| {
                return self.firstOf(right_link);
            }

            while (curr.parent) |parent_link| {
                if (parent_link.dirOf(curr) == .left) {
                    return parent_link;
                }

                curr = parent_link;
            }

            return null;
        }

        // Generic tree utilities

        fn setRoot(self: *Self, link: ?*LinkType) void {
            self.root = link;
            if (link) |l| l.parent = null;
        }

        fn replaceChild(self: *Self, parent: ?*LinkType, child: *LinkType, replacement: ?*LinkType) void {
            if (parent) |p| {
                p.setChild(p.dirOf(child), replacement);
            } else {
                assert(self.root == child);
                self.setRoot(replacement);
            }
        }

        fn replaceLink(self: *Self, head: *LinkType, subst: *LinkType) void {
            subst.setChild(.left, head.getChild(.left));
            subst.setChild(.right, head.getChild(.right));
            subst.color = head.color;
            self.replaceChild(head.parent, head, subst);
        }

        fn rotate(self: *Self, dir: Dir, link: *LinkType) void {
            const parent = link.parent;
            const pivot = link.getChild(dir.inverse()) orelse unreachable;
            link.setChild(dir.inverse(), pivot.getChild(dir));
            pivot.setChild(dir, link);

            std.mem.swap(LinkType.Color, &pivot.color, &link.color);
            self.replaceChild(parent, link, pivot);
        }

        // Helper methods related to querying

        fn findIn(self: *Self, link: *LinkType, key: Key) ?*LinkType {
            const link_key = getKey(link);

            const dir = switch (compare(key, link_key)) {
                .eq => return link,
                .lt => Dir.left,
                .gt => Dir.right,
            };

            if (link.getChild(dir)) |child| {
                return self.findIn(child, key);
            } else {
                return null;
            }
        }

        fn firstOf(self: *Self, link: *LinkType) *LinkType {
            _ = self;
            var fst = link;
            while (fst.getChild(.left)) |left_link| {
                fst = left_link;
            }
            return fst;
        }

        // Insertion/removal logic

        // isAllowedUnder returns true if the given link is valid beneth a node with a given color.
        fn isAllowedUnder(link: ?*LinkType, n: LinkType.Color) bool {
            if (link) |l| {
                return l.color < n;
            } else {
                return true;
            }
        }

        // isNonZero returns true if a link represents a non-zero colored node.
        fn isNonZero(link: ?*LinkType) bool {
            if (link) |l| {
                return l.color > 0;
            } else {
                return false;
            }
        }

        fn insertInto(self: *Self, link: *LinkType, new_link: *LinkType, key: Key) void {
            const link_key = getKey(link);
            const dir = switch (compare(key, link_key)) {
                .eq, .lt => Dir.left,
                .gt => Dir.right,
            };
            if (link.getChild(dir)) |child| {
                self.insertInto(child, new_link, key);
            } else {
                link.setChild(dir, new_link);
                self.setColorFromParent(new_link, link);
            }
        }

        // setColorFromParent sets a valid color for a link based on its parent (given as parameter).
        fn setColorFromParent(self: *Self, link: *LinkType, parent: *LinkType) void {
            assert(link.parent == parent);

            if (parent.color == 0) {
                link.color = N;
            } else if (parent.color == 1) {
                link.color = 1;
                self.repairColorViolation(parent.dirOf(link), parent);
            } else {
                link.color = parent.color - 1;
            }
        }

        // repairColorViolation takes in a link which has the same (0-zero) as the given child and fixes it.
        // Only used during insertion.
        fn repairColorViolation(self: *Self, child_link_dir: Dir, link: *LinkType) void {
            assert(link.color > 0);
            assert(link.getChild(child_link_dir).?.color == link.color);

            if (link.parent) |parent| {
                const link_dir = parent.dirOf(link);
                const can_rotate = isAllowedUnder(parent.getChild(link_dir.inverse()), link.color);

                // Right now we always prefer to rotate over re-coloring.
                // There's some interesting trade-offs here: A plain re-coloring should be fastest.
                // However, if it also requires recursive repairing it's maybe not a good idea.
                // At the same time, eagerly rotating _may_ help balance the tree?
                // We need benchmarks to explore more.

                if (can_rotate) {
                    if (link_dir == child_link_dir) {
                        self.rotate(link_dir.inverse(), parent);
                    } else {
                        self.rotate(child_link_dir.inverse(), link);
                        self.rotate(link_dir.inverse(), parent);
                    }
                } else if (link.color < N) {
                    // We can't rotate, but we still have more colors to choose from.
                    link.color += 1;
                    if (parent.color == link.color) {
                        // Now we'll have to repear this one though.
                        self.repairColorViolation(parent.dirOf(link), parent);
                    }
                } else {
                    // We can't rotate and we've reached the maximum color. This means that
                    // our parent is 0-colored and we can push it down.
                    assert(parent.color == 0);
                    link.color = 0;

                    const other = parent.getChild(link_dir.inverse()) orelse unreachable;
                    assert(other.color > 0);
                    other.color = 0;

                    if (parent.parent) |gp| {
                        self.setColorFromParent(parent, gp);
                    } else {
                        assert(self.root == parent);
                        parent.color = 0;
                    }
                }
            } else {
                // We're at the root.
                link.color = 0;
            }
        }

        // removeLink removes a link which has (at least) one null-child (given as `dir`).
        fn removeLink(self: *Self, link: *LinkType, dir: Dir) void {
            assert(link.getChild(dir) == null);
            const child = link.getChild(dir.inverse());

            if (link.parent) |parent| {
                const new_dir = parent.dirOf(link);
                parent.setChild(new_dir, child);
                if (link.color == 0) {
                    // We removed a 0-colored node and.
                    self.repairZeroImbalance(parent, new_dir);
                }
            } else {
                assert(self.root == link);
                self.setRoot(child);
            }
        }

        // repairZeroImbalance takes in a link which has an imbalance in the 0-count
        // of its children. The path of the given `dir` has one less 0-colored node
        // than the other side.
        fn repairZeroImbalance(self: *Self, link: *LinkType, dir: Dir) void {
            // Check if the child is a non-zero node. If so, we can just flip it.
            if (link.getChild(dir)) |child| {
                if (child.color > 0) {
                    child.color = 0;
                    return;
                }
            }

            const other = link.getChild(dir.inverse()).?;

            if (other.color == 0) {
                if (isAllowedUnder(other.getChild(.left), N) and isAllowedUnder(other.getChild(.right), N)) {
                    other.color = N;

                    if (link.color > 0) {
                        link.color = 0;
                    } else if (link.parent) |parent| {
                        self.repairZeroImbalance(parent, parent.dirOf(link));
                    }
                } else if (isNonZero(other.getChild(dir.inverse()))) {
                    other.getChild(dir.inverse()).?.color = 0;
                    self.rotate(dir, link);
                } else if (isNonZero(other.getChild(dir))) {
                    other.getChild(dir).?.color = 0;
                    self.rotate(dir.inverse(), other);
                    self.rotate(dir, link);
                } else {
                    unreachable;
                }
            } else {
                self.rotate(dir, link);
                self.repairZeroImbalance(link, dir);
            }
        }
    };
}

pub fn MapNode(
    comptime N: usize,
    comptime Key: type,
    comptime Value: type,
) type {
    return struct {
        const Self = @This();

        key: Key,
        value: Value,
        link: Link(N) = .{},

        // Implements dot-builder interface.

        pub fn build(self: *Self, b: anytype) !void {
            try b.defNode(self, b.attrs().withLabel("key={}\ncolor={}", .{
                self.key,
                self.link.color,
            }));

            if (self.link.getChild(.left)) |child| {
                try b.defEdge(
                    self,
                    @fieldParentPtr(Self, "link", child),
                    b.attrs().withLabel("left", .{}),
                );
            }

            if (self.link.getChild(.right)) |child| {
                try b.defEdge(
                    self,
                    @fieldParentPtr(Self, "link", child),
                    b.attrs().withLabel("right", .{}),
                );
            }
        }

        pub fn writeId(self: *Self, w: anytype) !void {
            try w.print("{*}", .{self});
        }
    };
}

pub fn MapTree(
    comptime N: usize,
    comptime Key: type,
    comptime Value: type,
    comptime compare: fn (lhs: anytype, rhs: anytype) Order,
) type {
    const getKey = struct {
        fn getKey(link: *const Link(N)) Key {
            return @fieldParentPtr(MapNode(N, Key, Value), "link", link).key;
        }
    }.getKey;

    return Tree(N, Key, getKey, compare);
}

const tester = @import("tester.zig");

pub fn testInsertRemove(
    comptime N: usize,
    comptime Count: usize,
) !void {
    const Node = MapNode(N, usize, void);
    const NodeTree = MapTree(N, usize, void, std.math.order);

    var nodes: [Count]Node = undefined;

    var possible_nodes = std.ArrayList([Count]Node).init(testing.allocator);
    defer possible_nodes.deinit();

    // Here are some dragons: The arrays inside possible_nodes are only valid
    // when it's being copied into `nodes`. That is, the internal pointers all
    // point into `nodes`, but we keep them into `possible_nodes`. This is a
    // nice way of quickly being able to restore any set of nodes, making
    // it possible to test different types of inserts/removals on the same tree.

    const Context = struct {
        nodes: *[Count]Node,
        possible_nodes: *std.ArrayList([Count]Node),
        node_idx: usize = 0,

        pub fn onComplete(self: *@This(), builder: anytype) !void {
            self.node_idx = 0;
            const root_node = self.populate(builder, 0);
            var tree: NodeTree = .{ .root = &root_node.link };

            tree.validate() catch |err| {
                if (err != error.InvalidBalance) {
                    @panic("unexpected validation error");
                }
                return;
            };

            // Next we set the keys to 1, 3, 5, …
            var link = tree.first();
            var key: usize = 1;
            while (link) |l| : (key += 2) {
                var node = @fieldParentPtr(Node, "link", l);
                node.key = key;
                link = tree.next(l);
            }
            try self.possible_nodes.append(self.nodes.*);
        }

        fn populate(self: *@This(), builder: anytype, i: usize) *Node {
            var node = &self.nodes[self.node_idx];
            self.node_idx += 1;
            node.* = Node{
                .key = 0,
                .value = {},
            };
            node.link.color = @intCast(Link(N).Color, builder.getColor(i));
            if (builder.getLeft(i)) |child| {
                var child_node = self.populate(builder, child);
                node.link.setChild(.left, &child_node.link);
            }
            if (builder.getRight(i)) |child| {
                var child_node = self.populate(builder, child);
                node.link.setChild(.right, &child_node.link);
            }
            return node;
        }
    };

    const Builder = tester.RGBTreeBuilder(Count, N, *Context);

    var ctx = Context{
        .nodes = &nodes,
        .possible_nodes = &possible_nodes,
    };
    var b = Builder.init(&ctx);
    try tester.generate(Builder, &b, testing.allocator);

    for (possible_nodes.items) |n| {
        // Insert 0, 2, 4, …
        var key: usize = 0;
        while (key < Count * 2 + 1) : (key += 2) {
            nodes = n;
            var tree = NodeTree{ .root = &nodes[0].link };
            var node = Node{ .key = key, .value = {} };
            tree.insert(&node.link);
            try tree.validate();
        }

        // Remove 1, 3, 5, …
        key = 1;
        while (key < Count * 2) : (key += 2) {
            nodes = n;
            var tree = NodeTree{ .root = &nodes[0].link };
            var link = tree.find(key) orelse return error.NoSuchKey;
            var node = @fieldParentPtr(Node, "link", link);
            try testing.expectEqual(key, node.key);
            tree.remove(link);
            try tree.validate();
        }
    }
}

test "n=1" {
    comptime var count = 1;
    inline while (count < 10) : (count += 1) {
        try testInsertRemove(1, count);
    }
}

test "n=2" {
    comptime var count = 1;
    inline while (count < 8) : (count += 1) {
        try testInsertRemove(2, count);
    }
}

test "n=3" {
    comptime var count = 1;
    inline while (count < 6) : (count += 1) {
        try testInsertRemove(3, count);
    }
}
