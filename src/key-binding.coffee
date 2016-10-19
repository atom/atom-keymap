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
    @isMatchedModifierKeydownKeyupCache = null

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

  # Returns true iff the binding starts with one or more modifier keydowns and
  # ends with at a subset of matching modifier keyups.
  #
  # Bare modifier keydown combinations are not handled specially, e.g.
  # "ctrl ^ctrl" also returns true. The keymap manager ignores them, there's no
  # reason to do the additional work to identify them again here.
  isMatchedModifierKeydownKeyup: ->
    # this is likely to get checked repeatedly so we calc it once and cache it
    return @isMatchedModifierKeydownKeyupCache if @isMatchedModifierKeydownKeyupCache?

    if not @keystrokeArray?.length > 1
      return @isMatchedModifierKeydownKeyupCache = false

    lastKeystroke = @keystrokeArray[@keystrokeArray.length-1]
    if not lastKeystroke.startsWith('^')
      return @isMatchedModifierKeydownKeyupCache = false

    modifierKeysDown = getModifierKeys(@keystrokeArray[0])
    modifierKeysUp = getModifierKeys(lastKeystroke.substring(1))
    for keyup in modifierKeysUp
      if modifierKeysDown.indexOf(keyup) < 0
        return @isMatchedModifierKeydownKeyupCache = false
    return @isMatchedModifierKeydownKeyup = true
