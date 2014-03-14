{specificity} = require 'clear-cut'
[parser, fs, loophole, pegjs] = []

AtomModifiers = new Set
AtomModifiers.add(modifier) for modifier in ['ctrl', 'alt', 'shift', 'cmd']

BrowserModifiers = new Set
AtomModifiers.add(modifier) for modifier in ['Ctrl', 'Alt', 'Shift', 'Meta']

SpecificityCache = {}

exports.normalizeKeystrokes = (keystrokes) ->
  keystrokes.split(/\s+/)
    .map (keystroke) -> normalizeKeystroke(keystroke)
    .join(' ')

exports.keystrokeForKeyboardEvent = (event) ->
  unless BrowserModifiers.has(event.keyIdentifier)
    if event.keyIdentifier.indexOf('U+') is 0
      hexCharCode = event.keyIdentifier[2..]
      charCode = parseInt(hexCharCode, 16)
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
    key = key.toUpperCase() if /^[^a-z]$/.test(key)
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
  key = key.toUpperCase() if /^[a-z]$/.test(key) and shift
  if key.length is 1
    keyIdentifier = "U+#{key.charCodeAt(0).toString(16)}"
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

  for key in keys
    if AtomModifiers.has(key)
      modifiers.add(key)
    else
      primaryKey = key

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
