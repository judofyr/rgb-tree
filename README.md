# RGB tree

An _RGB tree_ is a generalization of the classical [Red-black tree](https://en.wikipedia.org/wiki/Red%E2%80%93black_tree) which supports more than two colors.
By introducing multiple colors the tree will be less balanced, but also require fewer rotations on insert.

This repository contains an implementation of an intrusive RGB tree in [Zig](https://ziglang.org/).

## Overview of data structure

An RGB tree is a binary search tree with the following properties:

- **Color:**
  Each node has a _color_ which is represented by an integer.
  An RGB tree of order `n` uses `n+1` possible colors: 0, 1, ..., `n`.
- **Decreasing colors:**
  Each node's color must be strictly smaller than its parent's color.
  E.g. if the parent's color is 3, then the node must have a color of 0, 1, or 2.
- **Special case for 0-colored parents:**
  If the parent's color is 0, then the node can have _any_ color.
  In a sense, every 0-colored node starts a new "sequence" of decreasing colors.
- **Balanced:**
  Every path from a given node to any of its descendant leaf noes goes through the same number of nodes with color of 0.

The way to think about an RGB tree is that the nodes with color of 0 forms a perfectly balanced tree, while the other nodes allow some imbalance in-between those nodes.
By requiring the colors to be decreasing we limit the amount imbalance in the full tree.
The more colors, the more imbalances we allow, and thus fewer rotations are needed during insertion/deletion.

An RGB tree of order 1 is equivalent to a red-black tree by interpreting the color 0 as black and 1 as red.

### Why would you use it?

Yes, that is also what I'm wondering about.
Honestly, this work is only motivated by curiosity, combined with me wanting to learn more Zig.

At the very least, you can always set `n=1` and you'll end up with a regular red-black tree.
They are quite useful and not at all trivial to implement.
Maybe you'll find this library useful for your red-black needs.

You could also try to increase `n` and see how that impacts the performance of your use case.
This should theoretically speed up inserts/removals at the cost of slowing down querying.
If you have a tree which is frequently modified _without querying_ (e.g. because your nodes can be accessed in another way) then this might be advantageous.

RGB trees have another interesting possibility:
A 0-colored node will have at most `2^n` descendants which are not 0-colored.
This makes it possible for the 0-colored nodes to (physically, in memory) be a single large block containing all of these descendants as well.
Each new 0-colored node denotes a new "block" of data.
This is similar to how B-trees are structured and is often useful when it's cheaper to access local memory.

### Related works

RGB trees were inspired by [Partitioned Binary Search Trees](http://www.scielo.org.mx/scielo.php?pid=S1405-55462019000401375&script=sci_arttext) (PBST).
They introduce a concept of "class nodes" which represents a "class" containing "simple nodes".
A simple node may reference either a simple node inside the same class or a class node (which is a different class).
Each node stores the _height_ inside its own class.
This is actually very similar to an RGB tree:
The "class nodes" are 0-colored nodes and the height of a node serves the same purpose as its color.
The color of a node in an RGB tree can be look at as an _approximation_ of its height when we partition the tree by the 0-colored nodes.
Being an approximation means that RGB trees require less maintenance:
In many operations we don't need to change the color of a node, but in a PBST the height of a node has to be maintained exact at all times.

## Usage in Zig

This library is designed as an _intrusive_ data structure.
All of the public methods (e.g. `insert`, `find`, `remove`) only deals with a _link_.
This is a tiny struct which _only_ contains information about children/parent/color.
In order to use this library you should create your own struct and embed the link as a field.
You initialize the tree with four parameters:

- `n`: The parameter of the RGB tree.
- `Key`: The type which is used for the _key_.
- `getKey(Link) -> Key`: A helper function which converts a link to a key.
  This will typically use `@fieldParentPtr`.
- `compare(anytype, anytype) Order`: Comparison function.

```zig
const rgb = @import("rgb-tree");

const Node = struct {
    birth_year: u32,

    link: rgb.Link(1) = .{},
};

fn linkToKey(link: *rgb.Link(1)) u32 {
    return @fieldParentPtr(Node, "link", link).key;
}

const Tree = rgb.Tree(
    1,               // Parameter N
    u32,             // Key type
    linkToKey,       // Link -> Key
    std.math.order,  // Compare function
);

var tree = Tree.init();

var node1 = Node{.birth_year = 1900};
tree.insert(&node1);

var link = tree.find(1900) orelse @panic("could not find it");
var node2 = @fieldParentPtr(Node, "link", link);

// node1 and node2 are actually the same thing!
```
