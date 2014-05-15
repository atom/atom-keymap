{specificity} = require 'clear-cut'
[parser, fs, loophole, pegjs] = []

AtomModifiers = new Set
AtomModifiers.add(modifier) for modifier in ['ctrl', 'alt', 'shift', 'cmd']

KeyboardEventModifiers = new Set
KeyboardEventModifiers.add(modifier) for modifier in ['Control', 'Alt', 'Shift', 'Meta']

SpecificityCache = {}

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
    if event.keyIdentifier.indexOf('U+') is 0
      hexCharCode = event.keyIdentifier[2..]
      charCode = charCodeFromHexCharCode(hexCharCode, event.shiftKey)
      charCode = event.which if not isAscii(charCode) and isAscii(event.which)
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

exports.keydownEvent = (key, {ctrl, shift, alt, cmd, which, target}={}) ->
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
  Object.defineProperty(event, 'which', get: -> which) if which?
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

charCodeFromHexCharCode = (hexCharCode, shifted) ->
  charCode = parseInt(hexCharCode, 16)

  # Chromium includes incorrect keyIdentifier values on keypress events for
  # certain symbols keys on Linux and Windows.
  #
  # See https://code.google.com/p/chromium/issues/detail?id=51024
  # See https://bugs.webkit.org/show_bug.cgi?id=19906
  if process.platform is 'linux' or process.platform is 'win32'
    switch charCode
      when 186
        charCode = if shifted then 58 else 59 # ":" or ";"
      when 187
        charCode = if shifted then 43 else 61 # "+" or "="
      when 188
        charCode = if shifted then 60 else 44 # "<" or ","
      when 189
        charCode = if shifted then 95 else 45 # "_" or "-"
      when 190
        charCode = if shifted then 62 else 46 # ">" or "."
      when 191
        charCode = if shifted then 63 else 47 # "?" or "/"
      when 219
        charCode = if shifted then 123 else 91 # "{" or "["
      when 220
        charCode = if shifted then 124 else 92 # "|" or "\"
      when 221
        charCode = if shifted then 125 else 93 # "}" "]"
      when 222
        charCode = if shifted then 34 else 39 # '"' or "'"
      when 192
        charCode = if shifted then 126 else 96 # '~' or '`'
      when 49
        charCode = if shifted then 33 else 49 # '!' or '1'
      when 50
        charCode = if shifted then 64 else 50 # '@' or '2'
      when 51
        charCode = if shifted then 35 else 51 # '#' or '3'
      when 52
        charCode = if shifted then 36 else 52 # '$' or '4'
      when 53
        charCode = if shifted then 37 else 53 # '%' or '5'
      when 54
        charCode = if shifted then 94 else 54 # '^' or '6'
      when 55
        charCode = if shifted then 38 else 55 # '&' or '7'
      when 56
        charCode = if shifted then 42 else 56 # '*' or '8'
      when 57
        charCode = if shifted then 40 else 57 # '(' or '9'
      when 48
        charCode = if shifted then 41 else 48 # ')' or '0'

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
