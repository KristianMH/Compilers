# fasto-mode.el

This rough, incomplete document attempts to describe how fasto-mode.el works.
To install and use fasto-mode, read the instructions in the file itself.


# Language parts

This is a very condensed overview of the language parts of FASTO needed to make
a good Emacs mode.

## Function declaration

`fun TYPE ID (TYPE ID, ...) = EXP`

## Type

`int` `char` `bool`

`[a]`

## Keyword

`if` `then` `else` `let` `in` `fun` `fn` `op`

## Builtin

### Function

`iota` `replicate` `map` `reduce` `read` `write`

### Operator

`not` `+` `-` `==` `<` `~` `&&` `||`

## Literal

Types: string, character, number, array, boolean

## Variable declaration

`let ID = EXP in EXP`

## If then else

`if EXP then EXP else EXP`


# Highlighting

Emacs regexps handle highlighting just fine; see `fasto-font-lock`.


# Indentation

The difficult part of constructing the Emacs mode -- apart from Emacs Lisp's
many, many idiosyncracies -- is getting automatic indentation to work properly.

The primary goal is to indent as little as possible.  For example, we don't want
huge indentation in case of nested `let` expressions, like this:

    let x = 10 in
               let y = 20 in
                          let z = 30 in ...

For that, this should suffice:

    let x = 10 in
    let y = 20 in
    let z = 30 in ...

Take a look at `fasto-calculate-indentation` for the ugly details.  It handles
many special cases.
