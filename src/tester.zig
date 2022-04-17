const std = @import("std");

const assert = std.debug.assert;

// This file contains functionality for generating binary trees.
// We use this for testing that insertions and removals all maintain the required invariants.
//
// The concept is that you implement a stateful "builder" which has three methods:
//
// - generate() -> List of actions
// - apply(Action)
// - revert(Action)
//
// The `generate` function should return a list of actions which are valid in the
// current state. `apply` applies it to the current state while `revert` undoes it.
//
// We can then visit all actions in-depth.

const Frame = struct {
    left: usize,
    right: usize,
    next: usize,
};

pub fn generate(
    comptime Builder: type,
    builder: *Builder,
    allocator: std.mem.Allocator,
) !void {
    // We store all possible actions in a single array, even across different states.
    // Next we have a separate arrays which stores "frames". This contains information
    // about which actions have been applied and the boundaries between the actions.
    //
    // Example:
    // - The first state generates actions A1, A2, A3.
    // - We apply A2, and then it generates actions A4, A5, A6.
    //
    // Then:
    // - actions will contain: [A1, A2, A3, A4, A5, A6]
    // - frames will contain:
    //     - left=0, next=2, right=3
    //     - left=3, next=3, right=6
    //
    // The algorithm is to always look at the latest frame. First undo the previous action
    // which was applied, then apply the next action and generate a new set of actions.

    var actions = std.ArrayList(Builder.Action).init(allocator);
    defer actions.deinit();

    var frames = std.ArrayList(Frame).init(allocator);
    defer frames.deinit();

    try builder.generate(&actions);
    try frames.append(.{ .left = 0, .right = actions.items.len, .next = 0 });

    while (frames.items.len > 0) {
        var frame = &frames.items[frames.items.len - 1];

        if (frame.next > frame.left) {
            // Revert the previous action
            const action = actions.items[frame.next - 1];
            try builder.revert(action);
        }

        if (frame.next == frame.right) {
            // We're done with all actions frame.
            assert(actions.items.len == frame.right);
            actions.shrinkRetainingCapacity(frame.left);
            _ = frames.pop();
            continue;
        }

        const action = actions.items[frame.next];
        try builder.apply(action);
        frame.next += 1;

        const left = actions.items.len;
        try builder.generate(&actions);
        const right = actions.items.len;
        if (left < right) {
            try frames.append(.{ .left = left, .right = right, .next = left });
        }
    }
}

// BinaryTreeBuilder builds all binary tree containing a specific amount of nodes.
pub fn BinaryTreeBuilder(
    // Number of nodes.
    comptime Count: usize,

    // Context used for the callback.
    comptime Context: type,
) type {
    return struct {
        const Self = @This();

        // How many possible nodes is there in the tree?
        pub const MaxNodes = @shlExact(1, Count) - 1;
        pub const NodeBitSet = std.bit_set.StaticBitSet(MaxNodes);

        pub const Action = usize;

        // This keeps track of nodes in the tree which are used.
        used_slots: NodeBitSet,
        // This keeps track of nodes in the tree which are available (e.g. they have a parent).
        free_slots: NodeBitSet,
        used_count: usize = 0,

        context: Context,

        pub fn init(context: Context) Self {
            var self = Self{
                .free_slots = NodeBitSet.initEmpty(),
                .used_slots = NodeBitSet.initEmpty(),
                .context = context,
            };
            // Mark the root as free.
            self.free_slots.set(0);
            return self;
        }

        pub fn generate(self: *const Self, list: *std.ArrayList(Action)) !void {
            if (self.used_count == Count) return;

            // Since we're enumerating all possible trees we need to take some
            // care to not enumerate symmetric/duplicate trees. We do this by
            // only picking free slots which comes _after_ the last used slot.

            var last_used: ?usize = null;
            var used_iter = self.used_slots.iterator(.{});
            while (used_iter.next()) |idx| {
                last_used = idx;
            }

            var free_iter = self.free_slots.iterator(.{});
            while (free_iter.next()) |idx| {
                if (last_used == null or idx > last_used.?) {
                    try list.append(idx);
                }
            }
        }

        pub fn apply(self: *Self, action: Action) !void {
            self.free_slots.unset(action);
            if (left(action)) |l| self.free_slots.set(l);
            if (right(action)) |l| self.free_slots.set(l);
            self.used_count += 1;
            self.used_slots.set(action);

            if (self.used_count == Count) {
                try self.context.onComplete(self);
            }
        }

        pub fn revert(self: *Self, action: Action) !void {
            self.free_slots.set(action);
            if (left(action)) |l| self.free_slots.unset(l);
            if (right(action)) |l| self.free_slots.unset(l);
            self.used_count -= 1;
            self.used_slots.unset(action);
        }

        pub fn getLeft(self: *Self, idx: usize) ?usize {
            if (left(idx)) |l| {
                if (self.used_slots.isSet(l)) return l;
            }
            return null;
        }

        pub fn getRight(self: *Self, idx: usize) ?usize {
            if (right(idx)) |l| {
                if (self.used_slots.isSet(l)) return l;
            }
            return null;
        }

        pub fn getParent(self: *Self, idx: usize) ?usize {
            _ = self;
            return parent(idx);
        }

        fn within(i: usize) ?usize {
            return if (i < MaxNodes) i else null;
        }

        fn left(i: usize) ?usize {
            return within(2 * i + 1);
        }

        fn right(i: usize) ?usize {
            return within(2 * i + 2);
        }

        fn parent(i: usize) ?usize {
            return if (i > 0) (i - 1) / 2 else null;
        }
    };
}

// RGBTreeBuilder builds all possible N-order RGB trees for a given number of nodes.
// Note that this will actually _not_ validate that the 0-count is balanced (since this is a bit tricky).
pub fn RGBTreeBuilder(
    // Number of nodes.
    comptime Count: usize,
    // N-parameter of RGB tree.
    comptime N: usize,
    // Context used for callbacks.
    comptime Context: type,
) type {
    return struct {
        const Self = @This();

        const BinaryBuilder = BinaryTreeBuilder(Count, struct {
            pub fn onComplete(self: @This(), binary_builder: anytype) !void {
                _ = self;
                const builder = @fieldParentPtr(Self, "binary_builder", binary_builder);
                builder.state = .coloring;
            }
        });

        const Coloring = struct {
            idx: usize,
            color: usize,
            is_last: bool,
        };

        pub const Action = union(enum) {
            build_tree: BinaryBuilder.Action,
            color: Coloring,
        };

        const State = enum {
            tree_building,
            coloring,
        };

        binary_builder: BinaryBuilder,
        context: Context,
        state: State = .tree_building,
        colors: [BinaryBuilder.MaxNodes]?usize = .{null} ** BinaryBuilder.MaxNodes,

        pub fn init(context: Context) Self {
            return Self{
                .binary_builder = BinaryBuilder.init(.{}),
                .context = context,
            };
        }

        pub fn generate(self: *Self, list: *std.ArrayList(Action)) !void {
            switch (self.state) {
                .tree_building => {
                    var inner = std.ArrayList(BinaryBuilder.Action).init(list.allocator);
                    defer inner.deinit();
                    try self.binary_builder.generate(&inner);
                    try list.ensureUnusedCapacity(inner.items.len);
                    for (inner.items) |inner_action| {
                        list.appendAssumeCapacity(.{ .build_tree = inner_action });
                    }
                },
                .coloring => {
                    var used = self.binary_builder.used_slots.iterator(.{});
                    var seen: usize = 0;
                    while (used.next()) |idx| {
                        seen += 1;

                        if (self.colors[idx] == null) {
                            const is_last = seen == self.binary_builder.used_count;

                            var max_color: usize = N;
                            if (self.binary_builder.getParent(idx)) |parent| {
                                const parent_color = self.colors[parent] orelse unreachable;
                                if (parent_color > 0) {
                                    max_color = parent_color - 1;
                                }
                            }

                            var color: usize = 0;
                            while (color <= max_color) : (color += 1) {
                                try list.append(.{ .color = .{ .idx = idx, .color = color, .is_last = is_last } });
                            }

                            return;
                        }
                    }
                },
            }
        }

        pub fn apply(self: *Self, action: Action) !void {
            switch (action) {
                .build_tree => |a| try self.binary_builder.apply(a),
                .color => |c| {
                    self.colors[c.idx] = c.color;
                    if (c.is_last) {
                        try self.context.onComplete(self);
                    }
                },
            }
        }

        pub fn revert(self: *Self, action: Action) !void {
            switch (action) {
                .build_tree => |a| {
                    try self.binary_builder.revert(a);
                    self.state = .tree_building;
                },
                .color => |c| {
                    self.colors[c.idx] = null;
                },
            }
        }

        pub fn getLeft(self: *Self, i: usize) ?usize {
            return self.binary_builder.getLeft(i);
        }

        pub fn getRight(self: *Self, i: usize) ?usize {
            return self.binary_builder.getRight(i);
        }

        pub fn getColor(self: *Self, i: usize) usize {
            return self.colors[i] orelse unreachable;
        }
    };
}

const testing = std.testing;

test "generate tree" {
    const Context = struct {
        counter: usize = 0,

        fn onComplete(self: *@This(), builder: anytype) !void {
            _ = builder;
            self.counter += 1;
        }
    };

    const Builder = BinaryTreeBuilder(3, *Context);
    var ctx = Context{};
    var b = Builder.init(&ctx);
    try generate(Builder, &b, testing.allocator);
    try testing.expectEqual(@as(usize, 5), ctx.counter);
}

test "generate RGB tree" {
    const Context = struct {
        counter: usize = 0,

        fn onComplete(self: *@This(), builder: anytype) !void {
            _ = builder;
            self.counter += 1;
        }
    };

    const Builder = RGBTreeBuilder(3, 1, *Context);
    var ctx = Context{};
    var b = Builder.init(&ctx);
    try generate(Builder, &b, testing.allocator);
    try testing.expectEqual(@as(usize, 25), ctx.counter);
}
