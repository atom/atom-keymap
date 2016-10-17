{calculateSpecificity, MODIFIERS, getModKeys} = require './helpers'

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
    @isMatchedModifierKeydownKeyup = null

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

  # Returns true iff the binding starts with one or more modifier keydowns and ends
  # with the matching set of modifier keyups.
  #
  # The modifier key order in each must match. Bare modifier keydown
  # combinations are not handled specially, e.g. "ctrl ^ctrl" also returns true.
  # The keymap manager ignores them, there's no reason to do the additional work
  # to identify them again here.
  is_matched_modifer_keydown_keyup: ->
    # this is likely to get checked repeatedly so we calc it once and cache it
    return @isMatchedModifierKeydownKeyup if @isMatchedModifierKeydownKeyup?

    if not @keystrokeArray?.length > 1
      return @isMatchedModifierKeydownKeyup = false

    last_keystroke = @keystrokeArray[@keystrokeArray.length-1]
    if not last_keystroke.startsWith('^')
      return @isMatchedModifierKeydownKeyup = false

    mod_keys_down = getModKeys(@keystrokeArray[0])
    mod_keys_up = getModKeys(last_keystroke.substring(1))
    if mod_keys_down.length != mod_keys_up.length
      return @isMatchedModifierKeydownKeyup = false
    for i in [0..mod_keys_down.length-1]
      if mod_keys_down[i] != mod_keys_up[i]
        return @isMatchedModifierKeydownKeyup = false
    return @isMatchedModifierKeydownKeyup = true
