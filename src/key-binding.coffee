{calculateSpecificity, MODIFIERS, getModifierKeys, MATCH_TYPES} = require './helpers'


MATCH_TYPES = {
  EXACT: 'exact'
  KEYDOWN_EXACT: 'keydownExact'
  PARTIAL: 'partial'
}
module.exports.MATCH_TYPES = MATCH_TYPES

module.exports.KeyBinding =
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

  # userKeystrokes is an array of keystrokes e.g.
  # ['ctrl-y', 'ctrl-x', '^x']
  matchesKeystrokes: (userKeystrokes) ->
    userKeystrokeIndex = -1
    userKeystrokesHasKeydownEvent = false
    matchesNextUserKeystroke = (bindingKeystroke) ->
      while userKeystrokeIndex < userKeystrokes.length - 1
        userKeystrokeIndex += 1
        userKeystroke = userKeystrokes[userKeystrokeIndex]
        isKeydownEvent = not userKeystroke.startsWith('^')
        userKeystrokesHasKeydownEvent = true if isKeydownEvent
        if bindingKeystroke is userKeystroke
          return true
        else if isKeydownEvent
          return false
      null

    isPartialMatch = false
    bindingRemainderContainsOnlyKeyups = true
    bindingKeystrokeIndex = 0
    for bindingKeystroke in @keystrokeArray
      unless isPartialMatch
        doesMatch = matchesNextUserKeystroke(bindingKeystroke)
        if doesMatch is false
          return false
        else if doesMatch is null
          # Make sure userKeystrokes with only keyup events don't match everything
          if userKeystrokesHasKeydownEvent
            isPartialMatch = true
          else
            return false

      if isPartialMatch
        bindingRemainderContainsOnlyKeyups = false unless bindingKeystroke.startsWith('^')

    # Bindings that match the beginning of the user's keystrokes are not a match.
    # e.g. This is not a match. It would have been a match on the previous keystroke:
    # bindingKeystrokes = ['ctrl-tab', '^tab']
    # userKeystrokes    = ['ctrl-tab', '^tab', '^ctrl']
    return false if userKeystrokeIndex < userKeystrokes.length - 1

    if isPartialMatch and bindingRemainderContainsOnlyKeyups
      MATCH_TYPES.KEYDOWN_EXACT
    else if isPartialMatch
      MATCH_TYPES.PARTIAL
    else
      MATCH_TYPES.EXACT
