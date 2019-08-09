---
title: "Streaming Huffman Compression in Haskell (Part 2: Binary and Searches)"
categories: Haskell, Tutorials
tags: haskell
create-time: 2014/04/03 01:53:53
date: 2014/04/11 09:30:29
series: Huffman Compression, Beginner/Intermediate Haskell Projects
identifier: huffman-2
slug: streaming-huffman-compression-in-haskell-part-2-binary
old-slugs: 
entry-id: 23
---

Continuing on this series of beginner/intermediate projects for newer Haskell
users, let's look back at our Huffman encoding project.

In our [last post][] we went over two types of binary trees implemented as
algebraic data structures in Haskell, and also a scheme for assembling a
Huffman encoding tree using the State monad.

[last post]: http://blog.jle.im/entry/streaming-huffman-compression-in-haskell-part-1-trees

Now let's look at serializing and unserializing our prefix trees for easy
storage, and then at actually using them to encode and decode!

Binary
------

There are a couple of serialization libraries in Haskell; the dominant one is
[binary][], but [cereal][] is also not uncommon.  The two diverge on several
design points, and you can read up on them in the documentation for *cereal*.
We'll be using *binary* for the this tutorial; among many reasons, for its
easy integration with the *pipes* library we will be working with later.

[binary]: http://hackage.haskell.org/package/binary
[cereal]: http://hackage.haskell.org/package/cereal

### The Easy Way

So let's make `PreTree` serialize/unserializable.

The easy way is to enable the `DeriveGeneric` language extension on GHC, use
`deriving (Generic)` when we define our `PreTree`, and then:

~~~haskell
instance Binary a => Binary (PreTree a)
~~~

And...that's it!  We just auto-generated functions to serialize and
deserialize our `PreTree`s (if what they contain is itself serializable).

In real life, we would do this.  However, for the sake of learning, let's dig
a bit more into the `Binary` typeclass.

### The *Other* Easy Way

So the big crux of *binary* is the `Binary` typeclass:

~~~haskell
class Binary t where
    put :: t -> Put
    get :: Get t
~~~

where `Put` and `Get` are sort of "instruction objects for putting/getting
binary".  `Get` is a monad, and `Put` is a wrapped `PutM`, which is a writer
monad.  (To be more specific, `Put` is `PutM ()`, because the final action has
no result and only "writes")

So `Binary` things are things that you can serialize (with the instructions in
`put`) and deserialize (with the instructions in `get`).

Luckily, because of Haskell's great composition tools, assembling these
instructions by hand are easy peasy!

#### Put

Let's define our own custom `Put` for our `PreTree`s:

~~~haskell
!!!huffman/PreTree.hs "putPT ::" huffman-encoding
~~~

This all should be fairly readable and self-explanatory.

*   "To put a `PTLeaf x`, first put a flag saying you have a leaf, then
    put the value of `x`."

*   "To put a `PTNode pt1 pt2`, first put a flag saying you have a node, then
    put both trees."

Due to how monads and pattern matching work, the whole thing is pretty
expressive, pleasant to read, and satisfying to write.

The only slightly annoying thing is that we subject ourselves to [boolean
blindness][] by using `True` or `False`; we have to keep track of what means
what.  Alternatively, we can create our own binary data types, `data PTType =
IsNode | IsLeaf`, and `put` *that*, instead...but in this case it might not be
so bad to live with boolean blindness for now.

[boolean blindness]: http://existentialtype.wordpress.com/2011/03/15/boolean-blindness/

#### Get

Now let's define our own custom `Get`:

~~~haskell
!!!huffman/PreTree.hs "getPT ::" huffman-encoding
~~~

This also shouldn't be too bad!

*   "Get" the boolean flag, to tell you if you have a leaf or a node.
*   If it's a leaf, then `get` the data inside the leaf, and wrap it in a
    `PTLeaf`.
*   If it's not, `get` the next two `PreTree a`'s, and put them both in a
    `PTNode`.

The neat thing here is that `get` is polymorphic in its return type.  We know
that the first `get` expects a `Bool`, so it knows to parse a `Bool`.  We know
that the second `get` expects an `a`, so it knows to parse an `a`.  We know
that the final two `get`s both expect `PreTree a`'s, so it nows what to parse
for that too.

Hooray for type inference!

If you're not familiar with the `f <$> x <*> y` idiom, you can consider it to
be the same thing as `f x y`, except that `x` and `y` are "inside" things:

~~~haskell
ghci> (+) 1 4
5
ghci> (+) <$> Just 1 <*> Just 4
Just 5
~~~

Where `(<$>)` and `(<*>)` come from `Control.Applicative`.  We call this style
"applicative style", in the biz.

#### Wrapping it up

And finally, to tie it all together:

~~~haskell
!!!huffman/PreTree.hs "instance Binary a => Binary (PreTree a)" huffman-encoding
~~~

### Testing it out

However way we decide to write our `Binary` instance, let's test it all out.

~~~haskell
ghci> let (Just pt) = runBuildTree "hello world"
ghci> let encoded = encode pt
ghci> :t encoded
encoded :: ByteString       -- a string of bytes
ghci> let decoded = decode encoded :: PreTree Char
ghci> decoded
PTNode (PTNode (PTNode (PTLeaf 'h')
                       (PTLeaf 'e')
               )
               (PTNode (PTLeaf 'w')
                       (PTLeaf 'r')
               )
       )
       (PTNode (PTLeaf 'l')
               (PTNode (PTNode (PTLeaf 'd')
                               (PTLeaf ' ')
                       )
                       (PTLeaf 'o')
               )
       )
ghci> decoded == t
True
~~~

Neat!  We can also write it to a file and re-read:

~~~haskell
ghci> encodeFile "test.dat" t
ghci> t' <- decodeFile "test.dat" :: IO (PreTree Char)
ghci> t'
PTNode (PTNode (PTNode (PTLeaf 'h')
                       (PTLeaf 'e')
               )
               (PTNode (PTLeaf 'w')
                       (PTLeaf 'r')
               )
       )
       (PTNode (PTLeaf 'l')
               (PTNode (PTNode (PTLeaf 'd')
                               (PTLeaf ' ')
                       )
                       (PTLeaf 'o')
               )
       )
ghci> t' == t
True
~~~

And this looks like it works pretty well!

Encoding
--------

Now that we've got that out of the way, let's work on actually encoding and
decoding.

So, basically, we encode a character in a huffman tree by path you take to
reach the character.

Let's represent this path as a list of `Direction`s:

~~~haskell
!!!huffman/PreTree.hs "data Direction =" "type Encoding =" huffman-encoding
~~~

Eventually, an `Encoding` will be turned into a `ByteString`, with `DLeft`
representing the 0 bit and `DRight` representing the 1 bit.  But we keep them
as their own data types now because everyone hates [boolean blindness][].
Instead of keeping a `True` or `False`, we keep data types that actually carry
semantic meaning :)  And we can't do silly things like use a boolean as a
direction...what the heck?  Why would you even want to do that?  How is "true"
a direction?

### Direct search

Here's a naive recursive direct (depth-first) search.

~~~haskell
!!!huffman/PreTree.hs "findPT ::" huffman-encoding
~~~

The algorithm goes:

1.  If you find a `PTLeaf`, if the data matches what you are looking for,
    return the current path in a `Just`.  If not, this is a dead-end; return
    `Nothing`.

2.  If you find a `PTNode`, search the left branch adding a `DLeft` to the
    current path, and the right branch adding a `DRight` to the current path.
    Use `(<|>)` to perform the search lazily (ie, stop after the first
    success).

~~~haskell
ghci> let pt = runBuildTree "hello world"
ghci> findPT pt 'e'
Just [DLeft, DLeft, DRight]
ghci> findPT pt 'q'
Nothing
~~~


While it is clearly horribly inefficient, it does serve as a nice clean
example of a depth-first search (which exits as soon as it finds the goal),
and probably a nice reference implementation for us to reference later.

Its inefficiency lies in many things --- chiefly of those being the fact that
Huffman trees don't give you any real help as a search tree, and nothing short
of a full depth-first traversal would work.  Also, you probably don't want
to do this every time you want to encode something; you'd want to have some
sort of memoizing and caching, ideally.

### Pre-searching

We can sort of "solve" both of these problems this by traversing through our
`PreTree` and adding an entry to a `Map` at every leaf.  This fixes our
repetition problem by memoizing all of our results into a map...and it fixes
our search problem because `Map`s are an ordered binary search tree with
efficient O(log n) lookups.[^rewrite]

[^rewrite]: Note --- this section was largely rewritten; it used to contain a
rather involved yet misled tutorial about the Writer monad, as suggested by
old links/titles. This can [still be found here][oldwriter], if you want to
read through it.

[oldwriter]: https://github.com/mstksg/inCode/blob/master/copy/entries/.huffman-2-writer.md

There are many ways to do this; my favorite right now is to do it by doing
collapsing our tree into one giant map, using the Monoid instance of `Map`.

Basically, we turn each of our leaves into little `Map`s, and then "combine"
them all, using `(<>)`, which "combines" or merges two `Map k v`'s, using
their Monoid instance:

~~~haskell
!!!huffman/PreTree.hs "ptTable ::" huffman-encoding
~~~

We do some sort of fancy depth-first "map" over all of the leaves, keeping
track of how deep we are.  Then we combine it all as we go along with `<>`.

Note how it is almost identical in structure to `findPT`:

~~~haskell
!!!huffman/PreTree.hs "findPT ::" huffman-encoding
~~~

Except instead of doing a "short-circuit combination" with `(<|>)`, we do a
"full combination" with `(<>)`.


### Lookup, Act 2

So now that we have our lookup table, our new lookup/find function is both
simple and performant:

~~~haskell
!!!huffman/PreTree.hs "lookupPTTable ::" huffman-encoding
~~~

given, of course, that we generate our table first.

~~~haskell
ghci> let pt = runBuildTree "hello world"
ghci> let tb = fmap ptTable pt
ghci> tb >>= \tb' -> lookupPTTable tb' 'e'
Just [DLeft, DLeft, DRight]
ghci> tb >>= \tb' -> lookupPTTable tb' 'q'
Nothing
~~~

(Here we use the Monad instance for Maybe, to extract the `tb'` out of the
`Just tb`.  We "sequence" two Maybe's together.  For more information, check
out my [blog post][mp] on this exact topic)

[mp]: http://blog.jle.im/entry/practical-fun-with-monads-introducing-monadplus

### Encoding many

Now, we'd like to be able to decode an entire stream of `a`'s, returning a
list of the encodings.

~~~haskell
!!!huffman/PreTree.hs "encodeAll ::" huffman-encoding
~~~

This is a bit dense!  But I'm sure that you are up for it.

1.  First, we build the lookup table and call it `tb`.

2.  Then, we map `lookupPTTable tb` over our list `xs`, to get a list of type
    `[Maybe Encoding]`.

3.  Then, we use `sequence`, which in our case is `[Maybe a] -> Maybe [a]`.
    It turns a list of Maybe's into a list inside a Maybe.  Recall the
    semantics of the Maybe monad: If you ever encounter a `Nothing`, the
    *whole thing* is a `Nothing`.  So in this case, if *any* of the inputs are
    not decodable, *the entire thing is Nothing*.

    ~~~haskell
    ghci> sequence [Just 5, Just 4]
    Just [5,4]
    ghci> sequence [Just 6, Nothing]
    Nothing
    ~~~

    Note that the standard libraries provide a synonym for `sequence . map`
    --- `mapM`.  So we could have written it as `mapM (lookupPTTable t)
    xs`...but that is significantly less clear/immediately understandable.

4.  Recall that our `sequence` left us with a `Maybe [Encoding]`...but we only
    want `Maybe Encoding`.  So we can use `(<$>)` to `concat` all of the
    `Encoding`s inside the Maybe.

~~~haskell
ghci> let pt = runBuildTree "hello world"          -- :: Maybe (PreTree Char)
ghci> pt >>= \pt' -> encodeAll pt' "hello world"
Just [DLeft, DLeft, DLeft, DLeft, DLeft, DRight, DRight, DLeft, DRight, DLeft,
DRight, DRight, DRight, DRight, DRight, DLeft, DRight, DLeft, DRight, DLeft,
DRight, DRight, DRight, DLeft, DRight, DRight, DRight, DLeft, DRight, DRight,
DLeft, DLeft]
ghci> pt >>= \pt' -> encodeAll pt' "hello worldq"
Nothing
~~~

Welp, that's half the battle!

Decoding
--------

For huffman trees, decoding is the much simpler process.  Simply traverse down
the tree using the given encoding and return a value whenever you reach a
leaf.

~~~haskell
!!!huffman/PreTree.hs "decodePT ::" huffman-encoding
~~~

The logic should seem pretty familiar.  The main algorithm involves going down
the tree, "following" the direction list.  If you reach a leaf, then you have
found something (and return the directions you haven't followed yet).  If you
run out of directions while on a node...something has gone wrong.

~~~haskell
ghci> do  pt  <- runBuildTree "hello world"
    |     enc <- encodeAll pt "hello world"
    |     decodePT pt enc
Just ('h', [DLeft, DLeft ...])
~~~

(Here we are using the Maybe monad, in order to "stitch together" three
possibly-failing operations in a row.  We call `pt` and `enc` the values
"inside" the `Just pt` and `Just enc` returned by `runBuildTree` and
`encodeAll`; the whole thing fails if any of the steps fail at any time. If
you are not familiar with this, [I sort of literally wrote an entire blog
post][mp] on this subject :) )

### Decoding many

We'd like to repeatedly iterate this until we have consumed our entire
encoding.

Basically, starting with a list of encodings, we want to continually chop it
up and build a list from it.

This sounds a lot like the `Data.List` function `unfoldr`:

~~~haskell
unfoldr :: (b -> Maybe (a, b)) -> b -> [a]
~~~

`unfoldr` makes a list by applying your function repeatedly to a
"de-cumulator", carrying the state of the decumulator, and stopping when your
function returns `Nothing`.  You can think of it as the "opposite" of `foldr`.

Using `unfoldr`, we can write a `decodeAll`:

~~~haskell
!!!huffman/PreTree.hs "decodeAll ::" huffman-encoding
~~~

~~~haskell
ghci> do pt  <- runBuildTree "hello world"
 |    enc <- encodeAll pt "hello world"
 |    return (decodeAll pt enc)
~~~

Which works exactly as we'd like!

Testing
-------

We can write a utility to test our encoding/decoding functions:

~~~haskell
!!!huffman/Huffman.hs "testTree ::" huffman-encoding
~~~

(Again, refer to my [MonadPlus][mp] article from earlier, if you are
unfamiliar with working with the Maybe monad)

`testTree` should be an identity; that is, `testTree xs === xs`.

~~~haskell
ghci> testTree "hello world"
"hello world"
ghci> testTree "the quick brown fox jumps over the lazy dog"
"the quick brown fox jumps over the lazy dog"
~~~

Note the very unsafe irrefutable pattern match on `Just decoded`.  We'll fix
this later!

### QuickCheck

Now that we have a neat proposition, we can use `quickcheck` on it, from the
great [QuickCheck][] library.  `quickcheck` will basically test our
proposition `testTree xs == xs` by generating several random `xs`'s.

[QuickCheck]: http://hackage.haskell.org/package/QuickCheck

~~~haskell
ghci> import Test.QuickCheck
ghci> :set -XScopedTypeVariables
ghci> quickCheck (\(xs :: String) -> testTree xs == xs)
*** Failed! Falsifiable (after 3 tests and 2 shrinks):
"a"
~~~

#### Failure!

Oh!  We failed?  And on such a simple case?  What happened?

If we look at how `"a"` is encoded, it'll become apparent:

~~~haskell
ghci> let (Just pt) = runBuildTree "aaa"
ghci> pt
PTLeaf 'a'
ghci> findPT pt 'a'
Just []
ghci> encodeAll pt "aaaaaaaaaaa"
Just []
~~~

Ah.  Well, that's a problem.  Basically, our input string has
["zero" entropy][entropy], according to typical measurements.  So we cannot
naively huffman encode it.

[entropy]: http://en.wikipedia.org/wiki/Entropy_(information_theory)

#### Success!

There are a few ways to deal with this.  The most "immediate" way would be to
realize that `decodeAll` is partial (that is, it does not terminate/is
undefined on some of its inputs), and will actually never terminate if the
given tree is a singleton tree.  We can write a "safe" `decodeAll`:

~~~haskell
!!!huffman/PreTree.hs "decodeAll' ::" huffman-encoding
~~~

In doing this, we don't exactly "fix" the problem...we only defer
responsibility.  Now, whoever uses `decodeAll'` (like our eventual encoding
interface) is *forced to handle the error* (by handing the `Nothing` case). In
this way, *the type system enforces safety*.  Had we always used the unsafe
`decodeAll`, then whoever uses it eventually has to "manually remember" to
handle the unterminating case, by carefully reading documentation or something.
In this case, the type system is a big, explicit reminder saying "hey, deal
with the unterminating case."

We'll also a "safe" `testTree`:

~~~haskell
!!!huffman/Huffman.hs "testTree' ::" huffman-encoding
~~~

So we can now quickcheck:

~~~haskell
ghci> quickCheck (\(xs :: String) -> testTree' xs `elem` [Nothing, Just xs])
+++ OK, passed 100 tests.
~~~

Hooray!

### Re: Testing

All I'll admit that I didn't even anticipate the degenerate singleton tree
case until I decided to add a quickcheck section to this post.  It just goes
to show that you should always test!  And it also shows how easy it is to
write tests in quickcheck.  One line could mean five unit tests, and you might
even test edge/corner cases that you might have never even thought about!

For example, we probably should have tested `lookupPTTable` against `findPT`,
our reference implementation :)  We should have also tested our
binary encode/decode!

Next Time
---------

We're almost there!

For our last section, we are going to be focusing on pulling it all together
to make a streaming compression/decompression interface that will be able to
read a file and encode/decode into a new file as it goes, in constant memory,
using pipes.  After that, we will also be looking at how to profile code,
applying some optimization tricks we can do to get things just right, and
other things to wrap up.

