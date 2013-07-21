Import required libraries

    fs = require 'fs'
    path = require 'path'
    _  = require 'lodash'
    _.str = require 'underscore.string'
    _.mixin _.str.exports()
    nodeSass = require 'node-sass'

Custom error class

    class SassSyntaxError
        constructor: (@message, @lineNum) ->

The class representing single line

    class Line

Define some static properties

        wsRe = /^\s*/
        indentRe = /^( +|\t+)$/
        outputIndent = '  '

        constructor: (line, @lineNum) ->

Get the leading whitespace from the line

            lineIndent = line.match(wsRe)[0]

The rest is line content

            @lineContent = _.rtrim line[lineIndent.length..]

The line consisting of whitespace only is considered empty and not indented

            if not @lineContent
                lineIndent = ''

Check if indentation is done with spaces only or tabs only

            if lineIndent and not lineIndent.match(indentRe)
                throw new SassSyntaxError "Lines should be indented with spaces only or tabs only", @lineNum

Remember indentation character and length

            @indentChar = lineIndent[0]
            @indentLength = lineIndent.length

            @children = []

When the line is not inside of the comment rewrite it according to [http://sass-lang.com/docs/yardoc/file.INDENTED_SYNTAX.html#sass_syntax_differences]

        rewrite: (lineContent) ->
            lineContent = lineContent

Transform `:property value` to `property: value`

                .replace(/^:([\S-]+)\s+(.*)/, '$1: $2')

Remove extra spacing after colon

                .replace(/^([\S-]+):\s+(.*)/, '$1: $2')

Tranform shortcuts for `@mixin` and `@include`

                .replace(/^=\s*(.*)/, '@mixin $1')
                .replace(/^\+\s*(.*)/, '@include $1')

Quote unquoted `@import`s

            if (m = lineContent.match /^@import\s+(.+)/) and m[1][0] not in ["'", '"']
                lineContent = "@import \"#{m[1]}\""

Return transformed line

            lineContent

Output this line and all its children

        output: (inComment) ->

Instantly return if current line is empty

            if not @lineContent
                return ''

If not inside of commented block rewrite line content

            lineContent = @lineContent
            if not inComment
                lineContent = @rewrite(lineContent)

Is this line starting a commented block?

            parentMultiComment = _.startsWith(lineContent, '/*')
            parentSingleComment = _.startsWith(lineContent, '//')

Collect output bits in an array

            res = []

Output line indent
When inside of the comment block decrease the indent and add comment indicator

            level = @level
            if inComment
                level -= 1
            res.push _.repeat(outputIndent, level)

Hidden (//) comments are transformed into multiple SCSS single-line comments

            if inComment == '//'
                res.push '// '

Visible (/\*) comments are padded with asteris on every line

            if inComment == '/*'
                res.push ' * '

Output actual line content

            res.push lineContent

If this line is starting a content block pass the type of the block to its child lines

            if not inComment and (parentMultiComment or parentSingleComment)
                inComment = lineContent[...2]

If the line has children render them

            if @children.length

If not a comment block start SCSS block with `{`

                if not inComment
                    res.push ' {'

Iterate over child lines

                for i in [0...@children.length]
                    nextLine = @children[i].output(inComment)

Special error case when line in the middle of the `/*` block closes the block

                    if inComment == '/*' and i < @children.length - 1 and _.endsWith nextLine, '*/'
                        throw new SassSyntaxError "Multiline comment closed too early", @children[i].lineNum

Otherwise add this line to the output

                    res.push '\n' + nextLine

If not inside of the comments block close the SCSS block with `}`
Add it to the last child line to preserve line numbers

                if not inComment
                    res.push ' }'

If this line started the visible comment block and the last child line didn't close it add `*/`.
Add it to the last child line to preserve line numbers

                if parentMultiComment and not _.endsWith res[res.length-1], '*/'
                    res.push ' */'

If not inside of the comment block and the current line is a CSS rule (`property: value`) or rule part (`font: {...}`)
or is a mixin inclusion, close the line with semicolon

            if not inComment and (lineContent.match(/:( |$)/) or _.startsWith(lineContent, '@include'))
                res.push ';'

Return combined output

            res.join('')


The class representing the whole SASS document

    class Document

Helper method for error formatting

        indentCharName = (c) ->
            if c == ' ' then 'space' else 'tab'


Split the document into array of lines

        constructor: (doc) ->
            doc = doc.split '\n'
            @lines = []

We separately track empty lines numbers and add them later

            @emptyLines = []

Store document indentation scheme

            indentChar = null
            indentLength = null

Track the stack of processed lines to build proper hierarchy

            stack = []

Track previouls significant (non-empty) line to validate proper indentation

            prevSign = null

Iterate over document lines and parse them

            for i in [0...doc.length]
                line = new Line doc[i], i

Non-indented lines are at level 0

                if not line.indentChar
                    line.level = 0
                else

If thit is the first non-empty indented line pick the indentation scheme from it

                    if not indentChar
                        indentChar = line.indentChar
                        indentLength = line.indentLength

This line is obviously level 1

                        line.level = 1

Else make some checks

                    else

Indented lines must use the same indentation character

                        if line.indentLength and line.indentChar != indentChar
                            throw new SassSyntaxError "Previous lines indented with #{indentCharName(indentChar)}s,
                             but current line with #{indentCharName(line.indentChar)}s", i

Their indentation length must be a multiple if the base indentation

                        if line.indentLength % indentLength
                            throw new SassSyntaxError "Indent length must be multiple of #{indentLength}", i

The line level is defined by the line's depth when compared to basic indentation

                        line.level = line.indentLength / indentLength

If this is the first significant line it cannot be indented

                        if not prevSign and line.level
                            throw new SassSyntaxError "First line can not be indented", i

The line cannot be deeper than 1 level than the previous (significant) line

                        if prevSign and line.level > 1 + prevSign.level
                            throw new SassSyntaxError "Line can not be indented more than 1 level
                             deeper than the previous line", i

If the line is indented go through the stack to find ist parent line

                    if line.level
                        while stack.length and stack[stack.length-1].level != line.level - 1
                            stack.pop()
                        stack[stack.length-1].children.push line

If the line is not empty, remember it and add to the list of significant lines

                if line.lineContent
                    stack.push line
                    prevSign = line
                    @lines.push line

Else add its index to the list of empty lines indexes

                else
                    @emptyLines.push i

Return the converted document

        converted: ->

Iterate over all top-level lines (level 0)
All deeper lines will be rendered as their children

            res = []
            for line in @lines
                if not line.level
                    res.push line.output()

Combine the output and re-split it into separate lines

            res = res.join('\n').split('\n')

Insert empty lines into their original inxes to preserve line numbers

            for i in @emptyLines
                res.splice i, 0, ''

Re-join the lines

            res.join('\n')

    module.exports =

Convert given file to CSS or SCSS

        convert: (file, to='css') ->
            try

Read the file, wrap it into Sass Document and get it converted to SCSS

                sass = fs.readFileSync(file).toString()
                doc = new Document sass
                converted = doc.converted()

Catch errors, report and rethrow

            catch e
                console.log "Error on line ##{e.lineNum + 1}:", e.message
                throw e

If SCSS is desired format simply return

            if to == 'scss'
                return converted

Otherwise pass it to `node-sass`

            else
                return nodeSass.renderSync
                    data: converted
                    includePaths: [path.dirname file]
