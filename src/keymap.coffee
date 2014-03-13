KeyBinding = require './key-binding'
{keystrokeForKeyboardEvent} = require './helpers'

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
  keystrokeForKeyboardEvent: (event) ->
    keystrokeForKeyboardEvent(event)

  # Deprecated: Use {::addKeyBindings} instead.
  add: (bindings) ->
    @addKeyBindings(bindings)

  # Deprecated: Translate a jQuery keyboard event to a keystroke string. Use
  # {::keystrokeForKeyboardEvent} with a raw KeyboardEvent instead.
  keystrokeStringForEvent: (event) ->
    @keystrokeForKeyboardEvent(event.originalEvent ? event)
