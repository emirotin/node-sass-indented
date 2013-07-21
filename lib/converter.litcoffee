    fs = require 'fs'
    path = require 'path'
    _  = require 'lodash'
    _.str = require 'underscore.string'
    _.mixin _.str.exports()
    nodeSass = require 'node-sass'

    class SassSyntaxError
        constructor: (@message, @lineNum) ->

    class Line
        wsRe = /^\s*/
        indentRe = /^( +|\t+)$/
        outputIndent = '  '

        constructor: (line, @lineNum) ->
            lineIndent = line.match(wsRe)[0]
            @lineContent = _.rtrim line[lineIndent.length..]
            if not @lineContent # empty line should not be considered indented
                lineIndent = ''
            if lineIndent and not lineIndent.match(indentRe)
                throw new SassSyntaxError "Lines should be indented with spaces only or tabs only", @lineNum
            @indentChar = lineIndent[0]
            @indentLength = lineIndent.length

            @children = []

        rewrite: (lineContent) ->
            lineContent = lineContent
                .replace(/^:([\S-]+)\s+(.*)/, '$1: $2')
                .replace(/^([\S-]+):\s+(.*)/, '$1: $2')
                .replace(/^=\s*(.*)/, '@mixin $1')
                .replace(/^\+\s*(.*)/, '@include $1')
            if (m = lineContent.match /^@import\s+(.+)/) and m[1][0] not in ["'", '"']
                lineContent = "@import \"#{m[1]}\""
            lineContent

        output: (inComment) ->
            if not @lineContent
                return ''

            lineContent = @lineContent
            if not inComment
                lineContent = @rewrite(lineContent)

            parentMultiComment = _.startsWith(lineContent, '/*')
            parentSingleComment = _.startsWith(lineContent, '//')

            res = []

            level = @level
            if inComment
                level -= 1
            if inComment == '//'
                res.push '// '
            if inComment == '/*'
                res.push ' * '

            res.push _.repeat(outputIndent, level) + lineContent

            if not inComment and (parentMultiComment or parentSingleComment)
                inComment = lineContent[...2]

            if @children.length
                if not inComment
                    res.push ' {'
                for i in [0...@children.length]
                    nextLine = @children[i].output(inComment)
                    if inComment == '/*' and i < @children.length - 1 and _.endsWith nextLine, '*/'
                        throw new SassSyntaxError "Multiline comment closed too early", @children[i].lineNum
                    res.push '\n' + nextLine
                if not inComment
                    res.push ' }'
                if parentMultiComment and not _.endsWith res[res.length-1], '*/'
                    res.push ' */'

            if not inComment and (lineContent.match(/:( |$)/) or _.startsWith(lineContent, '@include'))
                res.push ';'
            res.join('')


    class Document
        indentCharName = (c) ->
            if c == ' ' then 'space' else 'tab'

        constructor: (doc) ->
            doc = doc.split '\n'

            @lines = []
            @emptyLines = []
            indentChar = null
            indentLength = null

            stack = []
            signLines = []
            prevSign = null

            for i in [0...doc.length]
                line = doc[i]
                line = new Line line, i

                if not line.indentChar
                    line.level = 0
                else
                    if not indentChar
                        indentChar = line.indentChar
                        indentLength = line.indentLength
                        line.level = 1
                    else
                        if line.indentLength and line.indentChar != indentChar
                            throw new SassSyntaxError "Previous lines indented with #{indentCharName(indentChar)}s,
                             but current line with #{indentCharName(line.indentChar)}s", i
                        if line.indentLength % indentLength
                            throw new SassSyntaxError "Indent length must be multiple of #{indentLength}", i
                        line.level = line.indentLength / indentLength
                        if not prevSign and line.level
                            throw new SassSyntaxError "First line can not be indented", i
                        if prevSign and line.level > 1 + prevSign.level
                            throw new SassSyntaxError "Line can not be indented more than 1 level
                             deeper than the previous line", i

                    if line.level
                        while stack.length and stack[stack.length-1].level != line.level - 1
                            stack.pop()
                        stack[stack.length-1].children.push line

                if line.lineContent
                    stack.push line
                    prevSign = line
                    @lines.push line
                else
                    @emptyLines.push i

        converted: ->
            res = []
            for line in @lines
                if not line.level
                    res.push line.output()
            res = res.join('\n').split('\n')
            for i in @emptyLines
                res.splice i, 0, ''
            res.join('\n')

    convert = (file, to='css') ->
        try
            sass = fs.readFileSync(file).toString()
            doc = new Document sass
            converted = doc.converted()
        catch e
            console.log "Error on line ##{e.lineNum + 1}:", e.message
            throw e
        if to == 'scss'
            return converted
        else
            return nodeSass.renderSync
                data: converted
                includePaths: [path.dirname file]

    module.exports =
        convert: convert