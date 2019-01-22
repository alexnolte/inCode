Tries with Recursion Schemes
============================

> Originally posted by [Justin Le](https://blog.jle.im/).
> [Read online!](https://blog.jle.im/entry/tries-with-recursion-schemes.html)

Not too long ago, I was browsing the [prequel memes
subreddit](https://www.reddit.com/r/PrequelMemes) --- a community built around
creative ways of remixing and re-contextualizing quotes from the cinematic
corpus of the three Star Wars prequel movies --- when I noticed that a fad was
in progress [constructing tries based on quotes as
keys](https://www.reddit.com/r/PrequelMemes/comments/9w59t4/i_expanded_it/)
indexing stills from the movie corresponding to those quotes.

This inspired me to try playing around with some tries myself, and it gave me an
excuse to play around with
*[recursion-schemes](https://hackage.haskell.org/package/recursion-schemes)*
(one of my favorite Haskell libraries). If you haven't heard about it yet,
*recursion-schemes* (and the similar library
*[data-fix](https://hackage.haskell.org/package/data-fix)*) abstracts over
common recursive functions written on recursive data types. It exploits the fact
that a lot of recursive functions for different recursive data types all really
follow the same pattern and gives us powerful tools for writing cleaner and
safer code.

Recursion schemes is a perfect example of those amazing accidents that happen
throughout the Haskell ecosystem: an extremely "theoretically beautiful"
abstraction that also happens to be extremely useful for writing industrially
rigorous code.

Tries are a common intermediate-level recursive data type, and recursion-schemes
is a common intermediate-level library. So, as a fun intermediate-level Haskell
project, let's build a trie data type in Haskell based on recursion-schemes, to
see what it has to offer! The resulting data type will definitely not be a "toy"
--- it'll be something you can actually use to build meme diagrams of your own!

Trie
----

A [trie](https://en.wikipedia.org/wiki/Trie) (prefix tree) is a classic example
of a simple yet powerful data type most people encounter in school (I remember
being introduced to it through a project implementing a boggle solver).

Wikipedia has a nice picture:

![Sample Trie from Wikipedia, indexing lists of Char to
Ints](/img/entries/trie/wiki-trie.png "An example Trie")

API-wise, it is very similar to an *associative map*, like the `Map` type from
*[containers](https://hackage.haskell.org/package/containers/docs/Data-Map-Lazy.html)*.
It stores "keys" to "values", and you can insert a value at a given key, lookup
the value stored at a given key, or delete the value at a given key.

The main difference is in implementation: the keys are *strings of tokens*, and
it is internally represented as a tree: if your keys are words, then the first
level is the first letter, the second level is the letter, etc. In the example
above, the trie stores the keys `to`, `tea`, `ted`, `ten`, `A`, `i`, `in`, and
`inn`, to the values 7, 3, 4, 12, 15, 11, 5, and 9, respectively. Note that it
is possible for one key to completely overlap another (like `in` storing 5, and
`inn` storing 9). In the usual case, however, we have partial overlaps (like
`tea`, storing 3, and `ted` storing 4), whose common prefix (`te`) has no value
stored under it.

Haskell Tries
-------------

We can represent this in Haskell by representing each layer as a `Map` of a
token to the next "level" of the trie:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/trie/trie.hs#L27-L28

data Trie k v = MkT (Maybe v) (Map k (Trie k v))
  deriving Show
```

A `Trie k v` will have keys of type `[k]`, where `k` is the key token type, and
values of type `v`. Each layer might have a value (`Maybe v`), and branches out
to each new layer.

We could write the trie storing `(to, 9)`, `(ton, 3)`, and `(tax, 2)` as:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/trie/trie.hs#L43-L56

testTrie :: Trie Char Int
testTrie = MkT Nothing $ M.fromList [
      ('t', MkT Nothing $ M.fromList [
          ('o', MkT (Just 9) $ M.fromList [
              ( 'n', MkT (Just 3) M.empty )
            ]
          )
        , ('a', MkT Nothing $ M.fromList [
              ( 'x', MkT (Just 2) M.empty )
            ]
          )
        ]
      )
    ]
```

Note that this implementation isn't particularly structurally sound, since it's
possible to represent invalid keys that have branches that lead to nothing. This
mostly becomes troublesome when we implement `delete`, but we won't be worrying
about that for now. The nice thing about Haskell is that we can be as safe as we
want or need, as a judgement call on a case-by-case basis. However, a
"correct-by-construction" trie is in the next part of this series :)

### Enter Recursion Schemes

Now, `Trie` as we write it up there is an explicitly recursive data type. While
this is common practice, it's not a particularly ideal one. The problem with
explicitly recursive data types is that to work with them, you often rely on
explicitly recursive functions.

Explicitly recursive functions are notoriously difficult to write, understand,
and maintain. It's extremely easy to accidentally write an infinite loop, and is
often called "the GOTO of functional programming".

So, there's a trick we can use to "factor out" the recursion in our data type.
The trick is to replace the recursive occurrence of `Trie a` (in the `Cons`
constructor) with a "placeholder" variable:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/trie/trie.hs#L30-L31

data TrieF k v x = MkTF (Maybe v) (Map k x)
  deriving (Functor, Show)
```

`TrieF` now represents, essentially, "one layer" of a `Trie`.

There are now two paths we can go down: we can re-implement `Trie` in terms of
`TrieF` (something that most tutorials and introductions do), or we can think of
`TrieF` as a "non-recursive view" into `Trie`. It's a way of *working* with
`Trie a` *as if* it were a non-recursive data type.

That's because *recursion-schemes* gives combinators (called "recursion
schemes") to abstract over common explicit recursion patterns. The key to using
*recursion-schemes* is to recognize which combinators abstracts over the type of
recursion you're using. You then give that combinator an algebra or a coalgebra
(more on this later), and you're done!

Learning how to use *recursion-schemes* effectively is basically picking the
right recursion scheme that abstracts over the type of function you want to
write for your data type. It's all about becoming familiar with the "zoo" of
(colorfully named) recursion schemes you can pick from, and identifying which
one does the job in your situation.

That's the high-level view --- let's dive into writing out the API of our
`Trie`!

### Linking the base

One thing we need to do before we can start: we need to tell *recursion-schemes*
to link `TrieF` with `Trie`. In the nomenclature of *recursion-schemes*, `TrieF`
is known as the "base type", and `Trie` is called "the fixed-point".

Linking them requires some boilerplate, which is basically converting back and
forth from `Trie` to `TrieF`.

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/trie/trie.hs#L33-L41

type instance Base (Trie k v) = TrieF k v

instance Recursive (Trie k v) where
    project :: Trie k v -> TrieF k v (Trie k v)
    project (MkT v xs) = MkTF v xs

instance Corecursive (Trie k v) where
    embed :: TrieF k v (Trie k v) -> Trie k v
    embed (MkTF v xs) = MkT v xs
```

Basically we just link the constructors and fields of `MkT` and `MkTF` together.

As with all boilerplate, it is sometimes useful to clean it up a bit using
Template Haskell. The *recursion-schemes* library offers such splice:

``` {.haskell}
data Trie k v = MkT (Maybe v) (Map   k (Trie k v))
  deriving Show

makeBaseFunctor ''Trie
```

This will define `TrieF`, the `Base` type family instance, and the `Recursive`
and `Corecursive` instances (in possibly a more efficient way than the way we
wrote by hand, too).

Exploring the Zoo
-----------------

Time to explore the zoo a bit!

Whenever you get a new recursive type and base functor, a good "first thing" to
try out is testing out `cata` and `ana` (catamorphisms and anamorphisms), the
basic "folder" and "unfolder".

### Hakuna My Cata

Catamorphisms are functions that "combine" or "fold" every layer of our
recursive type into a single value. If we want to write a function of type
`Trie k v -> A`, we can reach first for a catamorphism.

Catamorphisms work by folding layer-by-layer, from the bottom up. We can write
one by defining "what to do with each layer". This description comes in the form
of an "algebra" in terms of the base functor:

``` {.haskell}
myAlg :: TrieF k v A -> A
```

If we think of `TrieF k v a` as "one layer" of a `Trie k v`, then
`TrieF k v A -> A` describes how to fold up one layer of our `Trie k v` into our
final result value (here, of type `A`). Remember that a `TrieF k v A` contains a
`Maybe v` and a `Map k A`. The `A` (the values of the map) contains the result
of folding up all of the original subtries along each key; it's the "results so
far".

And then we can use `cata` to "fold" our value along the algebra:

``` {.haskell}
cata myAlg :: Trie k v -> A
```

`cata` starts from the bottom-most layer, runs `myAlg` on that, then goes up a
layer, running `myAlg` on the results, then goes up another layer, running
`myAlg` on those results, etc., until it reaches the top layer and runs `myAlg`
again to produce the final result.

For example, we'll write a catamorphism that counts how many values/leaves we
have in our Trie into an `Int`.

``` {.haskell}
countAlg :: TrieF k v Int -> Int
```

This is the basic structure of an algebra: our final result becomes the
parameter of `TrieF k v`, and also the result of our algebra.

Remember that a `Trie k v` contains a `Maybe v` and a `Map k (Trie k v)`, and a
`TrieF k v Int` contains a `Maybe v` and a `Map k Int`. The `Map`, then,
represents the number of values inside all of the original subtries along each
key.

Basically, our task is "How to find a count, given a map of sub-counts".

With this in mind, we can write `countAlg`:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/trie/trie.hs#L61-L66

countAlg :: TrieF k v Int -> Int
countAlg (MkTF v subtrieCounts)
    | isJust v  = 1 + subtrieTotal
    | otherwise = subtrieTotal
  where
    subtrieTotal = sum subtrieCounts
```

If `v` is indeed a leaf (it's `Just`), then it's one plus the total counts of
all of the subtees (remember, the `Map k Int` contains the counts of all of the
original subtries, under each key). Otherwise, it's just the total counts of all
of the original subtries.

Our final `count` is therefore just:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/trie/trie.hs#L58-L59

count :: Trie k v -> Int
count = cata countAlg
```

``` {.haskell}
ghci> count testTrie
3
```

We can do something similar by writing a summer, as well:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/trie/trie.hs#L68-L72

trieSumAlg :: Num a => TrieF k a a -> a
trieSumAlg (MkTF v subtrieSums) = fromMaybe 0 v + sum subtrieSums

trieSum :: Num a => Trie k a -> a
trieSum = cata trieSumAlg
```

``` {.haskell}
ghci> trieSum testTrie
14
```

In the algebra, the `Map k a` contains the sum of all of the subtries. The
algebra therefore just adds up all of the subtrie sums with the value at that
layer. "How to find a sum, given a map of sub-sums".

#### Outside-In

Catamorphisms are naturally "inside-out", or "bottom-up". However, some
operations are more naturally "outside-in", or "top-down". One immediate example
is `lookup :: [k] -> Trie k v -> Maybe v`, which is clearly "top-down": it first
descends down the first item in the `[k]`, then the second, then the third, etc.
until you reach the end, and return the `Maybe v` at that layer.

In this case, it helps to invert control: instead of folding into a `Maybe v`
directly, fold into a "looker upper", a `[k] -> Maybe v`. We generate a "lookup
function" from the bottom-up, and then run that all in the end on the key we
want to look up.

Our algebra will therefore have type:

``` {.haskell}
lookupperAlg
    :: Ord k
    => TrieF k v ([k] -> Maybe v)
    -> ([k] -> Maybe v)
```

A `TrieF k v ([k] -> Maybe v)` contains a `Maybe v` and a
`Map k ([k] -> Maybe v)`, or a map of "lookuppers". Indexed at each key is
function of how to look up a given key in the original subtrie.

So, we are tasked with "how to implement a lookupper, given a map of
sub-lookuppers".

To do this, we can pattern match on the key we are looking up. If it's `[]`,
then we just return the current leaf (if it exists). Otherwise, if it's `k:ks`,
we can *run the lookupper of the subtrie at key `k`*.

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/trie/trie.hs#L82-L97

lookupperAlg
    :: Ord k
    => TrieF k v ([k] -> Maybe v)
    -> ([k] -> Maybe v)
lookupperAlg (MkTF v lookuppers) = \case
    []   -> v
    k:ks -> case M.lookup k lookuppers of
      Nothing        -> Nothing
      Just lookupper -> lookupper ks

lookup
    :: Ord k
    => [k]
    -> Trie k v
    -> Maybe v
lookup ks t = cata lookupperAlg t ks
```

(Written using the -XLambdaCase extension, allowing for `\case` syntax)

``` {.haskell}
ghci> lookup "to" testTrie
Just 9
ghci> lookup "ton" testTrie
Just 3
ghci> lookup "tone" testTrie
Nothing
```

Note that because `Map`s have lazy keys by default, we only ever generate
"lookuppers" for subtries under keys that we eventually descend on; any other
subtries will be ignored (and no lookuppers are ever generated for them).

In the end, this version has all of the same performance characteristics as the
explicitly recursive one; we're assembling a "lookupper" that stops as soon as
it sees either a failed lookup (so it doesn't cause any more evaluation later
on), or stops when it reaches the end of its list.

#### I Think the System Works

We've now written a couple of non-recursive functions to "query" `Trie`. But
what was the point, again? What do we gain over writing explicit versions to
query Trie? Why couldn't we just write:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/trie/trie.hs#L74-L76

trieSumExplicit :: Num a => Trie k a -> a
trieSumExplicit (MkT v subtries) =
    fromMaybe 0 v + sum (fmap trieSumExplicit subtries)
```

instead of

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/trie/trie.hs#L78-L80

trieSumCata :: Num a => Trie k a -> a
trieSumCata = cata $ \(MkTF v subtrieSums) ->
    fromMaybe 0 v + sum subtrieSums
```

One major reason, like I mentioned before, is to avoid using *explicit
recursion*. It's extremely easy when using explicit recursion to accidentally
write an infinite loop, or to mess up your control flow somehow. It's basically
like using `GOTO` instead of `while` or `for` loops in imperative languages.
`while` and `for` loops are meant to abstract over a common type of looping
control flow, and provide a disciplined structure for them. They also are often
much easier to read, because as soon as you see "while" or "for", it gives you a
hint at programmer intent in ways that an explicit GOTO might not.

Another major reason is to allow you to separate concerns. Writing
`trieSumExplicit` forces you to think "how to fold this entire trie". Writing
`trieSumAlg` allows us to just focus on "how to fold *this immediate* layer".
You only need to ever focus on the immediate layer you are trying to sum --- and
never the entire trie. `cata` takes your "how to fold this immediate layer"
function and turns it into a function that folds an entire trie, taking care of
the recursive descent for you.

::: {.note}
**Aside**

Before we move on, I just wanted to mention that `cata` is not a magic function.
From the clues above, you might actually be able to implement it yourself. For
our `Trie`, it's:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/trie/trie.hs#L99-L100

cata' :: (TrieF k v a -> a) -> Trie k v -> a
cata' alg = alg . fmap (cata' alg) . project
```

First we `project :: Trie k v -> TrieF k v (Trie k v)`, to "de-recursive" our
type. Then we fmap our entire `cata alg :: Trie k v -> a`. Then we run the
`alg :: TrieF k v a -> a` on the result. Basically, it's
fmap-collapse-then-collapse.
:::

### Ana Montana

Anamorphisms are functions that "generate" or "unfold" a value of a recursive
type, layer-by-layer. If we want to write a function of type `A -> Trie k v`, we
can reach first for an anamorphism.

Anamorphisms work by unfolding "layer-by-layer", from the top down. We can write
one by defining "how to generate the next layer". This description comes in the
form of a "coalgebra" (pronounced like "co-algebra", and not like coal energy
"coal-gebra"), in terms of the base functor:

``` {.haskell}
myCoalg :: A -> TrieF k v A
```

If we think of `TrieF k v a` as "one layer" of a `Trie k v`, then
`A -> TrieF k v A` describes how to generate a new nested layer of our
`Trie k v` from our initial "seed" (here, of type `A`). Remember that a
`TrieF k v A` contains a `Maybe v` and a `Map k A`. The `A` (the values of the
map) are then used to seed the *new* subtries. The `A` is the "continue
expanding with..." value.

And then we can use `cata` to "unfold" our value along the coalgebra:

``` {.haskell}
ana myCoalg :: A -> Trie k v
```

`ana` starts from the an initial seed `A`, runs `myCoalg` on that, and then goes
down a layer, running `myCoalg` on each value in the map to create new layers,
etc., forever and ever. In practice, it usually stops when we return a `TrieF`
with an empty map, since there are no more seeds to expand down. However, it's
nice to remember we don't have to special-case this behavior: it arises
naturally from the structure of maps.

I don't think there's really too many canonical or classical anamorphisms that
are as generally applicable as summing and counting leaves, but the general idea
is that if you want to create a value by repeatedly "expanding leaves", an
anamorphism is a perfect fit.

An example here that fits will with the nature of a trie is to produce a
"singleton trie": a trie that has only a single value at a single trie.

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/trie/trie.hs#L105-L109

mkSingletonCoalg :: v -> ([k] -> TrieF k v [k])
mkSingletonCoalg v = singletonCoalg
  where
    singletonCoalg []     = MkTF (Just v) M.empty
    singletonCoalg (k:ks) = MkTF Nothing  (M.singleton k ks)
```

Given a `v` value, we'll make a coalgebra `[k] -> TrieF k v [k]`. Our "seed"
will be the `[k]` key we want to insert, and we'll generate our singleton key by
making sub-maps with sub-keys.

Our coalgebra ("layer generating function") goes like this:

1.  If our key-to-insert is empty `[]`, then we're here! We're at *the layer*
    where we want to insert the value at, so `MkTF (Just v) M.empty`.

2 If our key-to-insert is *not* empty, then we're not here! We return
`MkTF     Nothing`...but we know we leave a singleton map
`M.singleton k ks :: Map k [k]` leaving a single seed. When we run our coalgebra
with `ana`, `ana` will go down and expand out that single seed (with our
coalgebra) into an entire new sub-trie, with `ks` as its seed.

So, we have `singleton`:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/trie/trie.hs#L102-L103

singleton :: [k] -> v -> Trie k v
singleton k v = ana (mkSingletonCoalg v) k
```

We run the coalgebra on our initial seed (the key), and ana will run
`singletonCoalg` repeatedly, expanding out all of the seeds we deposit, forever
and ever (or at least until there are no more values of the seed type left,
which happens if we return an empty map).

``` {.haskell}
ghci> singleton "hi" 7
MkT Nothing $ M.fromList [
    ('h', MkT Nothing $ M.fromList [
        ('i', MkT (Just 7) M.empty )
      ]
    )
  ]
```

### Trie from Map

Now that we've got the basics, let's look at a more interesting anamorphism,
where we leave multiple "seeds" along many different keys in the map, to
generate many different subtries from our root.

Let's write a function to generate a `Trie k v` from a `Map [k] v`: Given a map
of keys (as token strings), generate a prefix trie containing every key-value
pair in the map.

This might sound complicated, but let's remember the philosophy and approach of
writing an anamorphism: "How do I generate *one layer*"?

Our `fromMapCoalg` will take a `Map [k] v` and generate `TrieF k v (Map [k] v)`:
*one single layer* of our new Trie (in particular, the *top layer*). And the
values in each of the resultant maps will be later then watered and expanded
into their own fully mature subtries.

So, how do we generate the *top layer* of a prefix trie from a map? Well,
remember, to make a `TrieF k v (Map [k] v)`, we need a `Maybe v` (the value at
this layer) and a `Map k (Map [k] v)` (the map of seeds that will each expand
into full subtries).

-   If the map contains `[]` (the empty string), then there *is a value* at this
    layer. We will return `Just`.
-   In the `Map k (Map [k] v)`, the value at key `k` will contain all of the
    key-value pairs in the original map that *start with k*, not including the
    `k`.

For a concrete example, if we start with
`M.fromList [("to", 9), ("ton", 3), ("tax", 2)]`, then we want `fromMapCoalg` to
produce:

``` {.haskell}
fromMap (M.fromList [("to", 9), ("ton", 3), ("tax", 2)])
    = MkTF Nothing (
          M.fromList [
            ('t', M.fromList [
                ("o" , 9)
              , ("on", 3)
              , ("ax", 2)
              ]
            )
          ]
        )
```

The value is `Nothing` because we don't have the empty string, and the map at
`t` contains all of the original key-value pairs that began with `t`.

Now that we have the concept, we can implement it using `Data.Map` combinators
like `M.lookup`, `M.mapMaybeWithKey`, and `M.unionsWith M.union`:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/trie/trie.hs#L111-L125

fromMapCoalg
    :: Ord k
    => Map [k] v
    -> TrieF k v (Map [k] v)
fromMapCoalg mp = MkTF (M.lookup [] mp)
                       (M.unionsWith M.union (M.mapMaybeWithKey descend mp))
  where
    descend []     _ = Nothing
    descend (k:ks) v = Just $ M.singleton k (M.singleton ks v)

fromMap
    :: Ord k
    => Map [k] v
    -> Trie k v
fromMap = ana fromMapCoalg
```

And just like that, we have a way to turn a `Map [k]` into a `Trie k`...all just
from describing how to make *the top-most layer*. `ana` extrapolates the rest!

Again, we can ask what the point of this is: why couldn't we just write it
directly recursively?

The answers again are the same: first, to avoid potential bugs from explicit
recursion. Second, to separate concerns: instead of thinking about how to
generate an entire trie, we only need to be think about how to generate a single
layer. `ana` reads our mind here, and extrapolates out the entire trie.

::: {.note}
**Aside**

Again, let's take some time to reassure ourselves that `ana` is not a magic
function. You might have been able to guess how it's implemented: it runs the
coalgebra, and then fmaps re-expansion recursively.

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/trie/trie.hs#L127-L128

ana' :: (a -> TrieF k v a) -> a -> Trie k v
ana' coalg = embed . fmap (ana' coalg) . coalg
```

First, we run the `coalg :: a -> TrieF k v a`, then we fmap our entire
`ana coalg :: a -> Trie k v`, then we
`embed :: TrieF k v (Trie k v) -> Trie k v` back into our recursive type.
:::

This is where the fun begins
----------------------------

So those are some examples to get our feet wet; now it's time to build our
prequel meme trie!

To render our tree, we're going to be using the
*[graphviz](https://hackage.haskell.org/package/graphviz)* library, which
generates a *[DOT
file](https://en.wikipedia.org/wiki/DOT_(graph_description_language))* which the
graphviz application can render. The *graphviz* library directly renders a value
of the graph data type from *[fgl](https://hackage.haskell.org/package/fgl)*,
the functional graph library that is the de-facto fully fleshed-out graph
manipulation library of the Haskell ecosystem.

So, the roadmap seems simple:

1.  Load our prequel memes into a `Map String PrequelMeme`, a map of quotes to
    their associated macro images 2 Use `ana` to turn a `Map String PrequelMeme`
    into a `Trie Char PrequelMeme`
2.  Use `cata` to turn a `Trie Char PrequelMeme` into a graph of nodes linked by
    letters, with prequel meme leaves
3.  Use the *graphviz* library to turn that graph into a DOT file, to be
    rendered by the external graphviz application.

1 and 4 are mainly fumbling around with IO and interfacing with libraries, so 2
and 3 are the interesting steps in our case. We actually already wrote 2 (in the
previous section --- surprise!), so that just leaves 3 to investigate.

### Generating the Graph

*fgl* provides a two (interchangeable) graph types; for the sake of this
article, we're going to be using `Gr` from the
*Data.Graph.Inductive.PatriciaTree* module.

The type `Gr a b` represents a graph of vertices with labels of type `a`, and
edges with labels of type `b`. In our case, for a `Trie k v`, we'll have a graph
with nodes of type `Maybe v` (the leaves, if they exist) and edges of type `k`
(the token linking one node to the next).

Our end goal, then, is to write a function `Trie k v -> Gr (Maybe v) k`. Knowing
this, we can jump directly into writing an algebra:

``` {.haskell}
trieGraphAlg
    :: TrieF k v (Gr (Maybe v) k)
    -> Gr (Maybe v) k
```

and then using `cata trieGraphAlg :: Trie k v -> Gr (Maybe v) k`.

This isn't a bad way to go about it, and you won't have *too* many problems.
However, this might be a good learning opportunity to try writing "monadic"
catamorphisms.

That's because to create a graph using *fgl*, you need to manage Node ID's,
which are represented as `Int`s. To add a node, you need to generate a fresh
Node ID. *fgl* has some nice tools for managing this, but we can have some
(completely unnecessary) fun by taking care of it ourselves.

We can use `State Int` as a way to generate "fresh" node ID's on-demand, with
the action `fresh`:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/trie/trie.hs#L146-L147

fresh :: State Int Int
fresh = state $ \i -> (i, i+1)
```

`fresh` will return the current counter state to produce a new node ID, and then
increment the counter so that the next invocation will return a new node ID.

In this light, our big picture is to write a
`Trie k v -> State Int (Gr (Maybe v) k)`: turn a `Trie k v` into a state action
to generate a graph.

To write this, we lay out our algebra:

``` {.haskell}
trieGraphAlg
    :: TrieF k v (State Int (Gr (Maybe v) k))
    -> State Int (Gr (Maybe v) k)
```

We have to write a function "how to make a state action creating a graph, given
a map of state actions creating sub-graphs".

One interesting thing to note is that we have a lot to gain from using
"first-class effects": `State Int (Gr (Maybe v) k)` is just a normal, inert
Haskell value that we can manipulate and sequence however we want. State is not
only explicit, but the sequencing of actions (as first-class values) is also
explicit.

We can write this using *fgl* combinators:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/trie/trie.hs#L154-L166

trieGraphAlg
    :: forall k v. ()
    => TrieF k v (State Int (Gr (Maybe v) k))
    -> State Int (Gr (Maybe v) k)
trieGraphAlg (MkTF v xs) = do
    n  <- fresh
    gs <- sequence xs
    let subroots :: [(k, Int)]
        subroots = M.toList . fmap (fst . G.nodeRange) $ gs
    pure $ G.insEdges ((\(k,i) -> (n,i,k)) <$> subroots)   -- insert root-to-subroots
         . G.insNode (n, v)                     -- insert new root
         . M.foldr (G.ufold (G.&)) G.empty      -- merge all subgraphs
         $ gs
```

1.  First, generate a fresh node label

2.  Then, sequence all of the state actions inside the map of sub-graph
    generators. Remember, a `TrieF k v (State Int (Gr (Maybe v) k))` contains a
    `Maybe v` and a `Map k (State Int (Gr (Maybe v) k))`. The map contains State
    actions to create the sub-graphs, and we use:

    ``` {.haskell}
    sequence
        :: Map k (State Int (Gr (Maybe v) k))
        -> State Int (Map k (Gr (Maybe v) k))
    ```

    To turn a map of subgraph-producing actions into an action producing a map
    of subgraphs.

3.  Next, it's useful to collect all of the subroots, `subroots :: [(k, Int)]`.
    These are all of the node id's of the roots of each of the subtrees, paired
    with the token leading to that subtree.

4.  Now to generate our result:

    a.  First we merge all subgraphs (using `G.ufold (G.&)` to merge together
        two graphs)
    b.  Then, we insert the new root, with our fresh node ID and the new
        `Maybe v` label.
    c.  Then, we insert all of the edges connecting our new root to the root of
        all our subgraphs (in `subroots`).

We can then write our graph generating function using this algebra, and then
running the resulting `State Int (Gr (Maybe v) k)` action:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/trie/trie.hs#L149-L152

trieGraph
    :: Trie k v
    -> Gr (Maybe v) k
trieGraph = flip evalState 0 . cata trieGraphAlg
```

--------------------------------------------------------------------------------

Hi, thanks for reading! You can reach me via email at <justin@jle.im>, or at
twitter at [\@mstk](https://twitter.com/mstk)! This post and all others are
published under the [CC-BY-NC-ND
3.0](https://creativecommons.org/licenses/by-nc-nd/3.0/) license. Corrections
and edits via pull request are welcome and encouraged at [the source
repository](https://github.com/mstksg/inCode).

If you feel inclined, or this post was particularly helpful for you, why not
consider [supporting me on Patreon](https://www.patreon.com/justinle/overview),
or a [BTC donation](bitcoin:3D7rmAYgbDnp4gp4rf22THsGt74fNucPDU)? :)
