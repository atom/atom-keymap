KeyBinding = require './key-binding'
Modifiers = ['Control', 'Alt', 'Shift', 'Meta']

module.exports =
class Keymap
  constructor: ->
    @keyBindings = []

  # Public: Add sets of key bindings grouped by CSS selector.
  #
  # source - A {String} (usually a path) uniquely identifying the given bindings
  #   so they can be removed later.
  # bindings - An {Object} whose top-level keys point at sub-objects mapping
  #   keystroke patterns to commands.
  addKeyBindings: (source, keyBindingsBySelector) ->
    for selector, keyBindings of keyBindingsBySelector
      # Verify selector is valid before registering any bindings
      try
        document.body.webkitMatchesSelector(selector)
      catch
        console.warn("Encountered an invalid selector adding keybindings from '#{source}': '#{selector}'")
        continue

      for keystroke, command of keyBindings
        keyBinding = new KeyBinding(source, command, keystroke, selector)
        @keyBindings.push(keyBinding)

  keyBindingsForCommand: (command) ->
    @keyBindings.filter (binding) -> binding.command is command

  # Public: Translate a keydown event to a keystroke string.
  #
  # event - A {KeyboardEvent} of type 'keydown'
  #
  # Returns a {String} describing the keystroke.
  keystrokeStringForKeyboardEvent: (event) ->
    unless event.keyIdentifier in Modifiers
      if event.keyIdentifier.indexOf('U+') is 0
        hexCharCode = event.keyIdentifier[2..]
        charCode = parseInt(hexCharCode, 16)
        charCode = event.which if not @isAscii(charCode) and @isAscii(event.which)
        key = @keyFromCharCode(charCode)
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

  keyFromCharCode: (charCode) ->
    switch charCode
      when 8 then 'backspace'
      when 9 then 'tab'
      when 13 then 'enter'
      when 27 then 'escape'
      when 32 then 'space'
      when 127 then 'delete'
      else String.fromCharCode(charCode)

  isAscii: (charCode) ->
    0 <= charCode <= 127

  # Deprecated: Use {::addKeyBindings} instead.
  add: (bindings) ->
    @addKeyBindings(bindings)

  # Deprecated: Translate a jQuery keyboard event to a keystroke string. Use
  # keystrokeStringForKeyboardEvent with a raw KeyboardEvent instead.
  keystrokeStringForEvent: (event) ->
    @keystrokeStringForKeyboardEvent(event.originalEvent ? event)
