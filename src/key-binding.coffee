{calculateSpecificity} = require './helpers'

module.exports =
class KeyBinding
  @currentIndex: 1

  enabled: true

  constructor: (@source, @command, @keystrokes, selector, @priority) ->
    @keystrokeArray = @keystrokes.split(' ')
    @keystrokeCount = @keystrokeArray.length
    @selector = selector.replace(/!important/g, '')
    @specificity = calculateSpecificity(selector)
    @index = @constructor.currentIndex++

  matches: (keystroke) ->
    multiKeystroke = /\s/.test keystroke
    if multiKeystroke
      keystroke is @keystroke
    else
      keystroke.split(' ')[0] is @keystroke.split(' ')[0]

  compare: (keyBinding) ->
    if keyBinding.priority is @priority
      if keyBinding.specificity is @specificity
        keyBinding.index - @index
      else
        keyBinding.specificity - @specificity
    else
      keyBinding.priority - @priority
