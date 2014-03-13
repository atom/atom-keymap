KeyBinding = require './key-binding'
{keystrokeForKeyboardEvent} = require './helpers'

Modifiers = ['Control', 'Alt', 'Shift', 'Meta']

module.exports =
class Keymap
  constructor: ->
    @keyBindings = []
    @keystrokes = []

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

  handleKeyboardEvent: (event) ->
    @keystrokes.push(@keystrokeForKeyboardEvent(event))
    keystrokeSequence = @keystrokes.join(' ')

    target = event.target
    while target? and target isnt document
      candidateBindings = @keyBindingsForKeystrokeSequenceAndTarget(keystrokeSequence, target)
      if candidateBindings.length > 0
        @keystrokes = []
        @dispatchCommandEvent(event, event.target, candidateBindings[0].command)
        event.preventDefault()
        return
      target = target.parentElement

  dispatchCommandEvent: (keyboardEvent, target, command) ->
    bubbles = true
    cancelable = false
    detail = {originalEvent: keyboardEvent}
    commandEvent = document.createEvent("CustomEvent")
    commandEvent.initCustomEvent(command, bubbles, cancelable, detail)
    target.dispatchEvent(commandEvent)

  keyBindingsForKeystrokeSequenceAndTarget: (keystrokeSequence, target) ->
    @keyBindings
      .filter (binding) ->
        binding.keystrokeSequence.indexOf(keystrokeSequence) is 0 \
          and target.webkitMatchesSelector(binding.selector)
      .sort (a, b) -> a.compare(b)

  keyBindingsForCommand: (command) ->
    @keyBindings.filter (binding) -> binding.command is command

  keyBindingsForKeystrokeSequence: (keystrokeSequence) ->
    @keyBindings.filter (binding) -> binding.keystrokeSequence.indexOf(keystrokeSequence) is 0

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

  # Deprecated: Handle a jQuery keyboard event. Use {::handleKeyboardEvent} with
  # a raw keyboard event instead.
  handleEvent: (event) ->
    @handleKeyboardEvent(event.originalEvent ? event)

  # Deprecated: Translate a jQuery keyboard event to a keystroke string. Use
  # {::keystrokeForKeyboardEvent} with a raw KeyboardEvent instead.
  keystrokeStringForEvent: (event) ->
    @keystrokeForKeyboardEvent(event.originalEvent ? event)
