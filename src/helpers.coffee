{calculateSpecificity} = require 'clear-cut'
KeyboardLayout = require 'keyboard-layout'

Modifiers = new Set(['ctrl', 'alt', 'shift', 'cmd'])
AtomModifierRegex = /(ctrl|alt|shift|cmd)$/
WhitespaceRegex = /\s+/
LowerCaseLetterRegex = /^[a-z]$/
UpperCaseLetterRegex = /^[A-Z]$/
ExactMatch = 'exact'
KeydownExactMatch = 'keydownExact'
PartialMatch = 'partial'
NonCharacterKeyNamesByDOM3Key = {
  'Control': 'ctrl',
  'Meta': 'cmd',
  'ArrowDown': 'down',
  'ArrowUp': 'up',
  'ArrowLeft': 'left',
  'ArrowRight': 'right'
}

isASCII = (character) -> character.charCodeAt(0) <= 127

isLatin = (character) -> character.charCodeAt(0) <= 0x024F

isUpperCaseLatin = (character) -> isLatin(character) and character.toLowerCase() isnt character

exports.normalizeKeystrokes = (keystrokes) ->
  normalizedKeystrokes = []
  for keystroke in keystrokes.split(WhitespaceRegex)
    if normalizedKeystroke = normalizeKeystroke(keystroke)
      normalizedKeystrokes.push(normalizedKeystroke)
    else
      return false
  normalizedKeystrokes.join(' ')

exports.keystrokeForKeyboardEvent = (event, dvorakQwertyWorkaroundEnabled) ->
  {ctrlKey, altKey, shiftKey, metaKey} = event
  isNonCharacterKey = event.key.length > 1

  if isNonCharacterKey
    key = NonCharacterKeyNamesByDOM3Key[event.key] ? event.key.toLowerCase()
  else
    key = event.key

    if altKey
      if process.platform is 'darwin'
        # When the option key is down on macOS, we need to determine whether the
        # the user intends to type an ASCII character that is only reachable by use
        # of the option key (such as option-g to type @ on a Swiss-German layout)
        # or used as a modifier to match against an alt-* binding.
        #
        # We check for event.code because test helpers produce events without it.
        if event.code and (characters = KeyboardLayout.getCurrentKeymap()[event.code])
          if shiftKey
            nonAltModifiedKey = characters.withShift
          else
            nonAltModifiedKey = characters.unmodified

          if not ctrlKey and not metaKey and isASCII(key) and key isnt nonAltModifiedKey
            altKey = false
          else
            key = nonAltModifiedKey
      else
        altKey = false if event.getModifierState('AltGraph')

  # Use US equivalent character for non-latin characters in keystrokes with modifiers
  if not isLatin(key) and (ctrlKey or altKey or metaKey)
    if characters = usCharactersForKeyCode(event.code)
      if event.shiftKey
        key = characters.withShift
      else
        key = characters.unmodified

  keystroke = ''
  if key is 'ctrl' or ctrlKey
    keystroke += 'ctrl'

  if key is 'alt' or altKey
    keystroke += '-' if keystroke.length > 0
    keystroke += 'alt'

  if key is 'shift' or (shiftKey and (isNonCharacterKey or isUpperCaseLatin(key)))
    keystroke += '-' if keystroke
    keystroke += 'shift'

  if key is 'cmd' or metaKey
    keystroke += '-' if keystroke
    keystroke += 'cmd'

  unless Modifiers.has(key)
    keystroke += '-' if keystroke
    keystroke += key

  keystroke = normalizeKeystroke("^#{keystroke}") if event.type is 'keyup'
  keystroke

exports.characterForKeyboardEvent = (event) ->
  event.key unless event.ctrlKey or event.metaKey

exports.calculateSpecificity = calculateSpecificity

exports.isAtomModifier = (keystroke) ->
  Modifiers.has(keystroke) or AtomModifierRegex.test(keystroke)

exports.keydownEvent = (key, options) ->
  return keyboardEvent(key, 'keydown', options)

exports.keyupEvent = (key, options) ->
  return keyboardEvent(key, 'keyup', options)

keyboardEvent = (key, eventType, {ctrl, shift, alt, cmd, keyCode, target, location}={}) ->
  ctrlKey = ctrl ? false
  altKey = alt ? false
  shiftKey = shift ? false
  metaKey = cmd ? false
  bubbles = true
  cancelable = true

  event = new KeyboardEvent(eventType, {
    key, ctrlKey, altKey, shiftKey, metaKey, bubbles, cancelable
  })

  if target?
    Object.defineProperty(event, 'target', get: -> target)
    Object.defineProperty(event, 'path', get: -> [target])
  event

# bindingKeystrokes and userKeystrokes are arrays of keystrokes
# e.g. ['ctrl-y', 'ctrl-x', '^x']
exports.keystrokesMatch = (bindingKeystrokes, userKeystrokes) ->
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
  for bindingKeystroke in bindingKeystrokes
    unless isPartialMatch
      doesMatch = matchesNextUserKeystroke(bindingKeystroke)
      if doesMatch is false
        return false
      else if doesMatch is null
        # Make sure userKeystrokes with only keyup events doesn't match everything
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
    KeydownExactMatch
  else if isPartialMatch
    PartialMatch
  else
    ExactMatch

normalizeKeystroke = (keystroke) ->
  if isKeyup = keystroke.startsWith('^')
    keystroke = keystroke.slice(1)
  keys = parseKeystroke(keystroke)
  return false unless keys

  primaryKey = null
  modifiers = new Set

  for key, i in keys
    if Modifiers.has(key)
      modifiers.add(key)
    else
      # only the last key can be a non-modifier
      if i is keys.length - 1
        primaryKey = key
      else
        return false

  if isKeyup
    primaryKey = primaryKey.toLowerCase() if primaryKey?
  else
    modifiers.add('shift') if UpperCaseLetterRegex.test(primaryKey)
    if modifiers.has('shift') and LowerCaseLetterRegex.test(primaryKey)
      primaryKey = primaryKey.toUpperCase()

  keystroke = []
  if not isKeyup or (isKeyup and not primaryKey?)
    keystroke.push('ctrl') if modifiers.has('ctrl')
    keystroke.push('alt') if modifiers.has('alt')
    keystroke.push('shift') if modifiers.has('shift')
    keystroke.push('cmd') if modifiers.has('cmd')
  keystroke.push(primaryKey) if primaryKey?
  keystroke = keystroke.join('-')
  keystroke = "^#{keystroke}" if isKeyup
  keystroke

parseKeystroke = (keystroke) ->
  keys = []
  keyStart = 0
  for character, index in keystroke when character is '-'
    if index > keyStart
      keys.push(keystroke.substring(keyStart, index))
      keyStart = index + 1

      # The keystroke has a trailing - and is invalid
      return false if keyStart is keystroke.length
  keys.push(keystroke.substring(keyStart)) if keyStart < keystroke.length
  keys

keyForKeyboardEvent = (event) ->

  keyIdentifier = event.keyIdentifier
  if process.platform in ['linux', 'win32']
    keyIdentifier = translateKeyIdentifierForWindowsAndLinuxChromiumBug(keyIdentifier)

  return keyIdentifier if KEYBOARD_EVENT_MODIFIERS.has(keyIdentifier)

  charCode = charCodeFromKeyIdentifier(keyIdentifier)

  if dvorakQwertyWorkaroundEnabled and typeof charCode is 'number'
    if event.keyCode is 46 # key code for 'delete'
      charCode = 127 # ASCII character code for 'delete'
    else
      charCode = event.keyCode

  if charCode?
    if process.platform in ['linux', 'win32']
      charCode = translateCharCodeForWindowsAndLinuxChromiumBug(charCode, event.shiftKey)

    if event.location is KeyboardEvent.DOM_KEY_LOCATION_NUMPAD
      # This is a numpad number
      charCode = numpadToASCII(charCode)

    charCode = event.which if not isASCII(charCode) and isASCII(event.keyCode)
    key = keyFromCharCode(charCode)
  else
    key = keyIdentifier.toLowerCase()

  # Only upper case alphabetic characters like 'a'
  if event.shiftKey
    key = key.toUpperCase() if LowerCaseLetterRegex.test(key)
  else
    key = key.toLowerCase() if UpperCaseLetterRegex.test(key)

  key

charCodeFromKeyIdentifier = (keyIdentifier) ->
  parseInt(keyIdentifier[2..], 16) if keyIdentifier.indexOf('U+') is 0

# Chromium includes incorrect keyIdentifier values on keypress events for
# certain symbols keys on Window and Linux.
#
# See https://code.google.com/p/chromium/issues/detail?id=51024
# See https://bugs.webkit.org/show_bug.cgi?id=19906
translateKeyIdentifierForWindowsAndLinuxChromiumBug = (keyIdentifier) ->
  WindowsAndLinuxKeyIdentifierTranslations[keyIdentifier] ? keyIdentifier

translateCharCodeForWindowsAndLinuxChromiumBug = (charCode, shift) ->
  if translation = WindowsAndLinuxCharCodeTranslations[charCode]
    if shift then translation.shifted else translation.unshifted
  else
    charCode

keyFromCharCode = (charCode) ->
  switch charCode
    when 8 then 'backspace'
    when 9 then 'tab'
    when 13 then 'enter'
    when 27 then 'escape'
    when 32 then 'space'
    when 127 then 'delete'
    else String.fromCharCode(charCode)

numpadToASCII = (charCode) ->
  NumPadToASCII[charCode] ? charCode

usKeymap = null
usCharactersForKeyCode = (code) ->
  usKeymap ?= require('./us-keymap')
  usKeymap[code]
