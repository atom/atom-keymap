{calculateSpecificity, MODIFIERS, getModifierKeys} = require './helpers'

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
    @isMatchedKeydownKeyupCache = null

  matches: (keystroke) ->
    multiKeystroke = /\s/.test keystroke
    if multiKeystroke
      keystroke == @keystroke
    else
      keystroke.split(' ')[0] == @keystroke.split(' ')[0]

  compare: (keyBinding) ->
    if keyBinding.priority is @priority
      if keyBinding.specificity is @specificity
        keyBinding.index - @index
      else
        keyBinding.specificity - @specificity
    else
      keyBinding.priority - @priority

  # Returns true iff the binding starts with one or more keydowns and
  # ends with a subset of matching keyups.
  isMatchedKeydownKeyup: ->
    # this is likely to get checked repeatedly so we calc it once and cache it
    return @isMatchedKeydownKeyupCache if @isMatchedKeydownKeyupCache?

    if not @keystrokeArray?.length > 1
      return @isMatchedKeydownKeyupCache = false

    lastKeystroke = @keystrokeArray[@keystrokeArray.length-1]
    if @keystrokeArray[0].startsWith('^') or not lastKeystroke.startsWith('^')
      return @isMatchedKeydownKeyupCache = false

    modifierKeysDown = getModifierKeys(@keystrokeArray[0])
    modifierKeysUp = getModifierKeys(lastKeystroke.substring(1))
    for keyup in modifierKeysUp
      if modifierKeysDown.indexOf(keyup) < 0
        return @isMatchedKeydownKeyupCache = false
    return isMatchedKeydownKeyupCache = true
