{calculateSpecificity, MODIFIERS, isKeyup} = require './helpers'

MATCH_TYPES = {
  EXACT: 'exact'
  PARTIAL: 'partial'
  PENDING_KEYUP: 'pendingKeyup'
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
    @cachedKeyups = null

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

  # Return the keyup portion of the binding, if any, as an array of
  # keystrokes.
  getKeyups: ->
    return @cachedKeyups if @cachedKeyups?
    for keystroke, i in @keystrokeArray
      return @cachedKeyups = @keystrokeArray.slice(i) if isKeyup(keystroke)

  # userKeystrokes is an array of keystrokes e.g.
  # ['ctrl-y', 'ctrl-x', '^x']
  matchesKeystrokes: (userKeystrokes) ->
    userKeystrokeIndex = -1
    userKeystrokesHasKeydownEvent = false
    matchesNextUserKeystroke = (bindingKeystroke) ->
      while userKeystrokeIndex < userKeystrokes.length - 1
        userKeystrokeIndex += 1
        userKeystroke = userKeystrokes[userKeystrokeIndex]
        isKeydownEvent = not isKeyup(userKeystroke)
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
      MATCH_TYPES.PENDING_KEYUP
    else if isPartialMatch
      MATCH_TYPES.PARTIAL
    else
      MATCH_TYPES.EXACT
