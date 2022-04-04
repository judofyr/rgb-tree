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

RGB trees have another interesting possibility:
A 0-colored node will have at most `2^n` connected descendants which are not 0-colored.
This makes it possible for the 0-colored nodes to (physically, in memory) be a single large block containing all of these descendants as well.
Then it behaves more like a B-tree which have many practical advantages today.

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
