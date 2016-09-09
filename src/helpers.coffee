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
NonPrintableKeyNamesByCode = {
  'AltLeft': 'alt',
  'AltRight': 'alt',
  'ControlLeft': 'ctrl',
  'ControlRight': 'ctrl',
  'MetaLeft': 'cmd',
  'MetaRight': 'cmd',
  'ShiftLeft': 'shift',
  'ShiftRight': 'shift',
  'ArrowDown': 'down',
  'ArrowUp': 'up',
  'ArrowLeft': 'left',
  'ArrowRight': 'right'
}

exports.normalizeKeystrokes = (keystrokes) ->
  normalizedKeystrokes = []
  for keystroke in keystrokes.split(WhitespaceRegex)
    if normalizedKeystroke = normalizeKeystroke(keystroke)
      normalizedKeystrokes.push(normalizedKeystroke)
    else
      return false
  normalizedKeystrokes.join(' ')

exports.keystrokeForKeyboardEvent = (event, dvorakQwertyWorkaroundEnabled) ->
  key = NonPrintableKeyNamesByCode[event.code]
  unless key?
    if characters = KeyboardLayout.charactersForKeyCode(event.code)
      key = characters.unmodified
  unless key?
    key = event.code.toLowerCase()

  keystroke = ''
  if event.ctrlKey or key is 'ctrl'
    keystroke += 'ctrl'

  if event.shiftKey
    if event.altKey
      if characters? and characters.withShiftAltGr.charCodeAt(0) <= 127 and not event.ctrlKey and not event.metaKey
        key = characters.withShiftAltGr
      else
        keystroke += '-' if keystroke.length > 0
        keystroke += 'alt'
    else
      if characters?
        key = characters.withShift
    unless /^[^A-Za-z]$/.test(key)
      keystroke += '-' if keystroke
      keystroke += 'shift'
  else if event.altKey
    if characters? and characters.withAltGr.charCodeAt(0) <= 127 and not event.ctrlKey and not event.metaKey
      key = characters.withAltGr
    else
      keystroke += '-' if keystroke.length > 0
      keystroke += 'alt'

  if event.metaKey or key is 'Meta'
    keystroke += '-' if keystroke
    keystroke += 'cmd'
  if key? and not Modifiers.has(key)
    keystroke += '-' if keystroke
    keystroke += key

  keystroke = normalizeKeystroke("^#{keystroke}") if event.type is 'keyup'
  keystroke

exports.characterForKeyboardEvent = (event, dvorakQwertyWorkaroundEnabled) ->
  unless event.ctrlKey or event.altKey or event.metaKey
    if key = keyForKeyboardEvent(event, dvorakQwertyWorkaroundEnabled)
      key if key.length is 1

exports.calculateSpecificity = calculateSpecificity

exports.isAtomModifier = (keystroke) ->
  Modifiers.has(keystroke) or AtomModifierRegex.test(keystroke)

exports.keydownEvent = (key, options) ->
  return keyboardEvent(key, 'keydown', options)

exports.keyupEvent = (key, options) ->
  return keyboardEvent(key, 'keyup', options)

keyboardEvent = (key, eventType, {ctrl, shift, alt, cmd, keyCode, target, location}={}) ->
  event = document.createEvent('KeyboardEvent')
  bubbles = true
  cancelable = true
  view = null

  key = key.toUpperCase() if LowerCaseLetterRegex.test(key)
  if key.length is 1
    keyIdentifier = "U+#{key.charCodeAt(0).toString(16)}"
  else
    switch key
      when 'ctrl'
        keyIdentifier = 'Control'
        ctrl = true if eventType isnt 'keyup'
      when 'alt'
        keyIdentifier = 'Alt'
        alt = true if eventType isnt 'keyup'
      when 'shift'
        keyIdentifier = 'Shift'
        shift = true if eventType isnt 'keyup'
      when 'cmd'
        keyIdentifier = 'Meta'
        cmd = true if eventType isnt 'keyup'
      else
        keyIdentifier = key[0].toUpperCase() + key[1..]

  location ?= KeyboardEvent.DOM_KEY_LOCATION_STANDARD
  event.initKeyboardEvent(eventType, bubbles, cancelable, view,  keyIdentifier, location, ctrl, alt, shift, cmd)
  if target?
    Object.defineProperty(event, 'target', get: -> target)
    Object.defineProperty(event, 'path', get: -> [target])
  Object.defineProperty(event, 'keyCode', get: -> keyCode)
  Object.defineProperty(event, 'which', get: -> keyCode)
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

isASCII = (charCode) ->
  0 <= charCode <= 127

numpadToASCII = (charCode) ->
  NumPadToASCII[charCode] ? charCode
