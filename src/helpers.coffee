{specificity} = require 'clear-cut'
[parser, fs, loophole, pegjs] = []

AtomModifiers = new Set
AtomModifiers.add(modifier) for modifier in ['ctrl', 'alt', 'shift', 'cmd']

AtomModifierRegex = /(ctrl|alt|shift|cmd)$/

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

NumPadToASCII =
  79: 47 # "/"
  74: 42 # "*"
  77: 45 # "-"
  75: 43 # "+"
  78: 46 # "."
  96: 48 # "0"
  65: 49 # "1"
  66: 50 # "2"
  67: 51 # "3"
  68: 52 # "4"
  69: 53 # "5"
  70: 54 # "6"
  71: 55 # "7"
  72: 56 # "8"
  73: 57 # "9"

exports.normalizeKeystrokes = (keystrokes) ->
  normalizedKeystrokes = []
  for keystroke in keystrokes.split(/\s+/)
    if normalizedKeystroke = normalizeKeystroke(keystroke)
      normalizedKeystrokes.push(normalizedKeystroke)
    else
      return false
  normalizedKeystrokes.join(' ')

exports.keystrokeForKeyboardEvent = (event, dvorakQwertyWorkaroundEnabled) ->
  preprocessedEvent = new PreprocessedKeyboardEvent(
    event, dvorakQwertyWorkaroundEnabled)

  keystroke = ''
  if preprocessedEvent.ctrlKey
    keystroke += 'ctrl'
  if preprocessedEvent.altKey
    keystroke += '-' if keystroke
    keystroke += 'alt'
  if preprocessedEvent.shiftKey
    # Don't push 'shift' when modifying symbolic characters like '{'
    unless /^[^A-Za-z]$/.test(preprocessedEvent.key)
      keystroke += '-' if keystroke
      keystroke += 'shift'
  if preprocessedEvent.metaKey
    keystroke += '-' if keystroke
    keystroke += 'cmd'
  if preprocessedEvent.key?
    keystroke += '-' if keystroke
    keystroke += preprocessedEvent.key

  keystroke

exports.calculateSpecificity = (selector) ->
  SpecificityCache[selector] ?= specificity(selector)

exports.isAtomModifier = (keystroke) ->
  AtomModifiers.has(keystroke) or AtomModifierRegex.test(keystroke)

exports.keydownEvent = (key, {ctrl, shift, alt, cmd, keyCode, target, location}={}) ->
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

  location ?= KeyboardEvent.DOM_KEY_LOCATION_STANDARD
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

# See http://www.w3.org/TR/2007/WD-DOM-Level-3-Events-20071221/events.html
# for the specification of KeyboardEvent that Chromium implements now.
class PreprocessedKeyboardEvent
  constructor: (event, dvorakQwertyWorkaroundEnabled) ->
    @keyIdentifier = event.keyIdentifier
    @charCode = event.charCode
    @keyCode = event.keyCode
    @key = event.key
    @which = event.which
    @location = event.location

    @ctrlKey = event.ctrlKey
    @altKey = event.altKey
    @shiftKey = event.shiftKey
    @metaKey = event.metaKey

    @original_event = event

    @preprocess(dvorakQwertyWorkaroundEnabled)

  preprocess: (dvorakQwertyWorkaroundEnabled) ->
    @populateCharCode()
    @workAroundDvorakQwerty() if dvorakQwertyWorkaroundEnabled
    @translateCharCodeForWindowsAndLinuxChromiumBug()
    @translateNumpadCharCode()
    @populateKey()
    @correctKeyCase()

  @charCodeFromKeyIdentifier: (keyIdentifier) ->
    parseInt(keyIdentifier[2..], 16) if keyIdentifier.indexOf('U+') is 0

  populateCharCode: ->
    @charCode = @constructor.charCodeFromKeyIdentifier(@keyIdentifier)

  workAroundDvorakQwerty: ->
    if typeof @charCode is 'number'
      @charCode = @keyCode

  # Chromium includes incorrect keyIdentifier values on keypress events for
  # certain symbols keys on Window and Linux.
  #
  # See https://code.google.com/p/chromium/issues/detail?id=51024
  # See https://bugs.webkit.org/show_bug.cgi?id=19906
  translateCharCodeForWindowsAndLinuxChromiumBug: ->
    if (process.platform is 'linux' or process.platform is 'win32') and
       (translation = WindowsAndLinuxCharCodeTranslations[@charCode])
      @charCode = if @shiftKey then translation.shifted else
                                    translation.unshifted

  @numpadToASCII: (charCode) ->
    NumPadToASCII[charCode] ? charCode

  translateNumpadCharCode: ->
    if @charCode? and @location is KeyboardEvent.DOM_KEY_LOCATION_NUMPAD
      @charCode = @constructor.numpadToASCII(@charCode)

  @isASCII: (charCode) ->
    0 <= charCode <= 127

  @keyFromCharCode: (charCode) ->
    switch charCode
      when 8 then 'backspace'
      when 9 then 'tab'
      when 13 then 'enter'
      when 27 then 'escape'
      when 32 then 'space'
      when 127 then 'delete'
      else String.fromCharCode(charCode)

  populateKey: ->
    unless KeyboardEventModifiers.has(@keyIdentifier)
      if @charCode?
        @charCode = @which if not @constructor.isASCII(@charCode) and
                              @constructor.isASCII(@keyCode)
        @key = @constructor.keyFromCharCode(@charCode)
      else
        @key = @keyIdentifier.toLowerCase()

  correctKeyCase: ->
    if @shiftKey
      @key = @key.toUpperCase() if /^[a-z]$/.test(@key)
    else
      @key = @key.toLowerCase() if /^[A-Z]$/.test(@key)
