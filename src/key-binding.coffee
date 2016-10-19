{calculateSpecificity} = require './helpers'

module.exports =
class KeyBinding
  KeyBinding.currentIndex = 1

  enabled: true

  constructor: (source, command, keystrokes, selector, priority) ->
    this.source = source
    this.command = command
    this.keystrokes = keystrokes
    this.priority = priority
    this.keystrokeArray = this.keystrokes.split(' ')
    this.keystrokeCount = this.keystrokeArray.length
    this.selector = selector.replace(/!important/g, '')
    this.specificity = calculateSpecificity(selector)
    this.index = this.constructor.currentIndex++

  matches: (keystroke) ->
    multiKeystroke = /\s/.test keystroke
    if multiKeystroke
      keystroke is this.keystroke
    else
      keystroke.split(' ')[0] is this.keystroke.split(' ')[0]

  compare: (keyBinding) ->
    if keyBinding.priority is this.priority
      if keyBinding.specificity is this.specificity
        keyBinding.index - this.index
      else
        keyBinding.specificity - this.specificity
    else
      keyBinding.priority - this.priority
