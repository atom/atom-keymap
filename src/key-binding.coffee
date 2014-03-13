{normalizeKeystrokeSequence, calculateSpecificity} = require './helpers'

module.exports =
class KeyBinding
  @currentIndex: 1

  constructor: (@source, @command, keystroke, selector) ->
    @keystroke = normalizeKeystrokeSequence(keystroke)
    @selector = selector.replace(/!important/g, '')
    @specificity = calculateSpecificity(selector)
    @index = KeyBinding.currentIndex++

  matches: (keystroke) ->
    multiKeystroke = /\s/.test keystroke
    if multiKeystroke
      keystroke == @keystroke
    else
      keystroke.split(' ')[0] == @keystroke.split(' ')[0]

  compare: (keyBinding) ->
    if keyBinding.specificity == @specificity
      keyBinding.index - @index
    else
      keyBinding.specificity - @specificity
