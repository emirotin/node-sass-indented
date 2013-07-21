This converts *Sass indented syntax* to *SCSS*.

The rules of syntax checking are:

1. Empty lines (lines consisting of whitespace only) are ignored and skipped in the following rules.
1. First line starting with whitespace defines the indent used in the whole file. It should only consist of all spaces or all tabs.
1. Any line's indent must be multiple of this initial indent. The coefficient defines line's `level`.
1. Any line's `level` can be less or equal to the previous line's one, or greater than it by 1.

The transformations applied are [http://sass-lang.com/docs/yardoc/file.INDENTED_SYNTAX.html#sass_syntax_differences]:

1. Whitespace-only lines are output as empty lines
1. `:propery value` => `property: value`
1. `=mixin-definition` => `@mixin mixin-definition`
1. `+mixin` => `@include mixin`
1. `@import unquoted/path` => `@import "unquoted/path"`
1. Sass _visible_ (nested under /\*) comments go to SCSS multi-line comments
1. Sass _hidden_ (nested under //) comments go to multiple SCSS single-line comments
1. Rule lines (`property: value`) are ended with semicolon
1. Nested blocks are wrapped with `{}` (closing `}` output at the end of the last nested line to preserve numbering)
1. If "selector" is actually a part of property (`font:`) the closing `}` is followed by semicolon

Export converter object

    module.exports = converter = require './converter'

TODO: When ran as program do CLI job

    path = require 'path'
    console.log converter.convert path.resolve __dirname + '/../test/test.sass'
