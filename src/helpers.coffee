{specificity} = require 'clear-cut'
[parser, fs, loophole, pegjs] = []

AtomModifiers = new Set
AtomModifiers.add(modifier) for modifier in ['ctrl', 'alt', 'shift', 'cmd']

KeyboardEventModifiers = new Set
KeyboardEventModifiers.add(modifier) for modifier in ['Control', 'Alt', 'Shift', 'Meta']

SpecificityCache = {}

WindowsAndLinuxCharCodeTranslations =
  48:
    shifted: 41    # ")"
    unshifted: 48  # "0"
  49:
    shifted: 33    # "!"
    unshifted: 49  # "1"
  50:
    shifted: 64    # "@"
    unshifted: 50  # "2"
  51:
    shifted: 35    # "#"
    unshifted: 51  # "3"
  52:
    shifted: 36    # "$"
    unshifted: 52  # "4"
  53:
    shifted: 37    # "%"
    unshifted: 53  # "5"
  54:
    shifted: 94    # "^"
    unshifted: 54  # "6"
  55:
    shifted: 38    # "&"
    unshifted: 55  # "7"
  56:
    shifted: 42    # "*"
    unshifted: 56  # "8"
  57:
    shifted: 40    # "("
    unshifted: 57  # "9"
  186:
    shifted: 58    # ":"
    unshifted: 59  # ";"
  187:
    shifted: 43    # "+"
    unshifted: 61  # "="
  188:
    shifted: 60    # "<"
    unshifted: 44  # ","
  189:
    shifted: 95    # "_"
    unshifted: 45  # "-"
  190:
    shifted: 62    # ">"
    unshifted: 46  # "."
  191:
    shifted: 63    # "?"
    unshifted: 47  # "/"
  192:
    shifted: 126   # "~"
    unshifted: 96  # "`"
  219:
    shifted: 123   # "{"
    unshifted: 91  # "["
  220:
    shifted: 124   # "|"
    unshifted: 92  # "\"
  221:
    shifted: 125   # "}"
    unshifted: 93  # "]"
  222:
    shifted: 34    # '"'
    unshifted: 39  # "'"

exports.normalizeKeystrokes = (keystrokes) ->
  normalizedKeystrokes = []
  for keystroke in keystrokes.split(/\s+/)
    if normalizedKeystroke = normalizeKeystroke(keystroke)
      normalizedKeystrokes.push(normalizedKeystroke)
    else
      return false
  normalizedKeystrokes.join(' ')

exports.keystrokeForKeyboardEvent = (event) ->
  unless KeyboardEventModifiers.has(event.keyIdentifier)
    charCode = charCodeFromKeyIdentifier(event.keyIdentifier)
    if charCode?
      if process.platform in ['linux', 'win32']
        charCode = translateCharCodeForWindowsAndLinuxChromiumBug(charCode, event.shiftKey)
      charCode = event.which if not isAscii(charCode) and isAscii(event.keyCode)
      key = keyFromCharCode(charCode)
    else
      key = event.keyIdentifier.toLowerCase()

  keystroke = []
  keystroke.push 'ctrl' if event.ctrlKey
  keystroke.push 'alt' if event.altKey
  if event.shiftKey
    # Don't push 'shift' when modifying symbolic characters like '{'
    keystroke.push 'shift' unless /^[^A-Za-z]$/.test(key)
    # Only upper case alphabetic characters like 'a'
    key = key.toUpperCase() if /^[a-z]$/.test(key)
  else
    key = key.toLowerCase() if /^[A-Z]$/.test(key)
  keystroke.push 'cmd' if event.metaKey
  keystroke.push(key) if key?
  keystroke.join('-')

exports.calculateSpecificity = (selector) ->
  SpecificityCache[selector] ?= specificity(selector)

exports.isAtomModifier = (key) ->
  AtomModifiers.has(key)

exports.keydownEvent = (key, {ctrl, shift, alt, cmd, keyCode, target}={}) ->
  event = document.createEvent('KeyboardEvent')
  bubbles = true
  cancelable = true
  view = null

  key = key.toUpperCase() if /^[a-z]$/.test(key)
  if key.length is 1
    keyIdentifier = "U+#{key.charCodeAt(0).toString(16)}"
  else
    switch key
      when 'ctrl'
        keyIdentifier = 'Control'
        ctrl = true
      when 'alt'
        keyIdentifier = 'Alt'
        alt = true
      when 'shift'
        keyIdentifier = 'Shift'
        shift = true
      when 'cmd'
        keyIdentifier = 'Meta'
        cmd = true
      else
        keyIdentifier = key[0].toUpperCase() + key[1..]

  location = KeyboardEvent.DOM_KEY_LOCATION_STANDARD
  event.initKeyboardEvent('keydown', bubbles, cancelable, view,  keyIdentifier, location, ctrl, alt, shift, cmd)
  Object.defineProperty(event, 'target', get: -> target) if target?
  Object.defineProperty(event, 'keyCode', get: -> keyCode)
  Object.defineProperty(event, 'which', get: -> keyCode)
  event

normalizeKeystroke = (keystroke) ->
  keys = parseKeystroke(keystroke)
  primaryKey = null
  modifiers = new Set

  for key, i in keys

    if AtomModifiers.has(key)
      modifiers.add(key)
    else
      # only the last key can be a non-modifier
      if i is keys.length - 1
        primaryKey = key
      else
        return false

  modifiers.add('shift') if /^[A-Z]$/.test(primaryKey)
  primaryKey = primaryKey.toUpperCase() if modifiers.has('shift') and /^[a-z]$/.test(primaryKey)

  keystroke = []
  keystroke.push('ctrl') if modifiers.has('ctrl')
  keystroke.push('alt') if modifiers.has('alt')
  keystroke.push('shift') if modifiers.has('shift')
  keystroke.push('cmd') if modifiers.has('cmd')
  keystroke.push(primaryKey) if primaryKey?
  keystroke.join('-')

parseKeystroke = (keystroke) ->
  unless parser?
    try
      parser = require './keystroke'
    catch e
      fs ?= require 'fs'
      loophole ?= require 'loophole'
      pegjs ?= require 'pegjs'
      keystrokeGrammar = fs.readFileSync(require.resolve('./keystroke.pegjs'), 'utf8')
      loophole.allowUnsafeEval => parser = pegjs.buildParser(keystrokeGrammar)

  parser.parse(keystroke)

charCodeFromKeyIdentifier = (keyIdentifier) ->
  parseInt(keyIdentifier[2..], 16) if keyIdentifier.indexOf('U+') is 0

# Chromium includes incorrect keyIdentifier values on keypress events for
# certain symbols keys on Window and Linux.
#
# See https://code.google.com/p/chromium/issues/detail?id=51024
# See https://bugs.webkit.org/show_bug.cgi?id=19906
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

isAscii = (charCode) ->
  0 <= charCode <= 127
