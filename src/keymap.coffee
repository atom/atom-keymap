season = require 'season'
fs = require 'fs-plus'
path = require 'path'
{Emitter} = require 'emissary'
{File} = require 'pathwatcher'
KeyBinding = require './key-binding'
{keystrokeForKeyboardEvent} = require './helpers'

Modifiers = ['Control', 'Alt', 'Shift', 'Meta']
Platforms = ['darwin', 'freebsd', 'linux', 'sunos', 'win32']
OtherPlatforms = Platforms.filter (platform) -> platform isnt process.platform

module.exports =
class Keymap
  Emitter.includeInto(this)

  constructor: (options) ->
    @defaultTarget = options?.defaultTarget
    @keyBindings = []
    @keystrokes = []
    @watchSubscriptions = {}

  destroy: ->
    for filePath, subscription of @watchSubscriptions
      subscription.off()

  # Public: Add sets of key bindings grouped by CSS selector.
  #
  # source - A {String} (usually a path) uniquely identifying the given bindings
  #   so they can be removed later.
  # bindings - An {Object} whose top-level keys point at sub-objects mapping
  #   keystroke patterns to commands.

  addKeyBindings: (source, keyBindingsBySelector) ->
    for selector, keyBindings of keyBindingsBySelector
      @addKeyBindingsForSelector(source, selector, keyBindings)

  # Public: Load the key bindings from the given path.
  #
  # path - A {String} containing a path to a file or a directory. If the path is
  #   a directory, all files inside it will be loaded.
  loadKeyBindings: (bindingsPath, options) ->
    checkIfDirectory = options?.checkIfDirectory ? true
    if checkIfDirectory and fs.isDirectorySync(bindingsPath)
      for filePath in fs.listSync(bindingsPath, ['.cson', '.json'])
        if @filePathMatchesPlatform(filePath)
          @loadKeyBindings(filePath, checkIfDirectory: false)
    else
      @addKeyBindings(bindingsPath, season.readFileSync(bindingsPath))
      @watchKeyBindings(bindingsPath) if options?.watch

  watchKeyBindings: (filePath) ->
    unless @watchSubscriptions[filePath]?.cancelled is false
      @watchSubscriptions[filePath] =
        new File(filePath).on 'contents-changed moved removed', =>
          @reloadKeyBindings(filePath)

  reloadKeyBindings: (filePath) ->
    try
      bindings = season.readFileSync(filePath)
      @removeKeyBindings(filePath)
      @addKeyBindings(filePath, bindings)
      @emit 'reloaded-key-bindings', filePath
    catch error
      console.warn("Failed to reload key bindings file: #{filePath}", error.stack ? error)

  # Determine if the given path should be loaded on this platform. If the
  # filename has the pattern '<platform>.cson' or 'foo.<platform>.cson' and
  # <platform> does not match the current platform, returns false. Otherwise
  # returns true.
  filePathMatchesPlatform: (filePath) ->
    otherPlatforms = @getOtherPlatforms()
    for component in path.basename(filePath).split('.')[0...-1]
      return false if component in otherPlatforms
    true

  # For testing purposes
  getOtherPlatforms: -> OtherPlatforms

  removeKeyBindings: (source) ->
    @keyBindings = @keyBindings.filter (keyBinding) -> keyBinding.source isnt source

  addKeyBindingsForSelector: (source, selector, keyBindings) ->
    # Verify selector is valid before registering any bindings
    try
      document.body.webkitMatchesSelector(selector.replace(/!important/g, ''))
    catch e
      console.warn("Encountered an invalid selector adding key bindings from '#{source}': '#{selector}'")
      return

    for keystroke, command of keyBindings
      keyBinding = new KeyBinding(source, command, keystroke, selector)
      @keyBindings.push(keyBinding)

  handleKeyboardEvent: (event) ->
    @keystrokes.push(@keystrokeForKeyboardEvent(event))
    keystrokes = @keystrokes.join(' ')

    target = event.target
    target = @defaultTarget if event.target is document.body and @defaultTarget?
    while target? and target isnt document
      candidateBindings = @keyBindingsForKeystrokesAndTarget(keystrokes, target)
      if candidateBindings.length > 0
        @keystrokes = []
        return if @dispatchCommandEvent(event, target, candidateBindings[0].command)
      target = target.parentElement

  dispatchCommandEvent: (keyboardEvent, target, command) ->
    return true if command is 'native!'
    keyboardEvent.preventDefault()
    commandEvent = document.createEvent("CustomEvent")
    commandEvent.initCustomEvent(command, bubbles = true, cancelable = true)
    commandEvent.originalEvent = keyboardEvent
    commandEvent.keyBindingAborted = false
    commandEvent.abortKeyBinding = ->
      @stopImmediatePropagation()
      @keyBindingAborted = true
    target.dispatchEvent(commandEvent)
    not commandEvent.keyBindingAborted

  keyBindingsForKeystrokesAndTarget: (keystrokes, target) ->
    @keyBindings
      .filter (binding) ->
        binding.keystrokes.indexOf(keystrokes) is 0 \
          and target.webkitMatchesSelector(binding.selector)
      .sort (a, b) -> a.compare(b)

  # Public: Get the key bindings for a given command and optional target.
  #
  # params - An {Object} whose keys constrain the binding search:
  #   :command - A {String} representing the name of a command, such as
  #     'editor:backspace'
  #   :target - An optional DOM element constraining the search. If this
  #     parameter is supplied, the call will only return bindings that can be
  #     invoked by a KeyboardEvent originating from the target element.
  findKeyBindings: (params={}) ->
    {command, target} = params

    bindings = @keyBindings

    if command?
      bindings = bindings.filter (binding) -> binding.command is command

    if target?
      candidateBindings = bindings
      bindings = []
      element = target
      while element? and element isnt document
        matchingBindings = candidateBindings
          .filter (binding) -> element.webkitMatchesSelector(binding.selector)
          .sort (a, b) -> a.compare(b)
        bindings.push(matchingBindings...)
        element = element.parentElement
    bindings

  # Public: Translate a keydown event to a keystroke string.
  #
  # event - A {KeyboardEvent} of type 'keydown'
  #
  # Returns a {String} describing the keystroke.
  keystrokeForKeyboardEvent: (event) ->
    keystrokeForKeyboardEvent(event)

  # Deprecated: Use {::addKeyBindings} instead.
  add: (source, bindings) ->
    @addKeyBindings(source, bindings)

  # Deprecated: Use {::removeKeyBindings} instead.
  remove: (source) ->
    @removeKeyBindings(source)

  # Deprecated: Handle a jQuery keyboard event. Use {::handleKeyboardEvent} with
  # a raw keyboard event instead.
  handleKeyEvent: (event) ->
    event = event.originalEvent ? event
    @handleKeyboardEvent(event)
    not event.defaultPrevented

  # Deprecated: Translate a jQuery keyboard event to a keystroke string. Use
  # {::keystrokeForKeyboardEvent} with a raw KeyboardEvent instead.
  keystrokeStringForEvent: (event) ->
    @keystrokeForKeyboardEvent(event.originalEvent ? event)

  # Deprecated: Use {::addKeyBindings} with a map from selectors to key
  # bindings.
  bindKeys: (source, selector, keyBindings) ->
    @addKeyBindingsForSelector(source, selector, keyBindings)

  # Deprecated: Use {::findKeyBindings} with the 'command' param.
  keyBindingsForCommand: (command) ->
    @findKeyBindings({command})

  # Deprecated: Use {::findKeyBindings} with the 'command' and 'target'
  # params
  keyBindingsForCommandMatchingElement: (command, target) ->
    @findKeyBindings({command, target: target[0] ? target})

  # Deprecated: Use {::findKeyBindings} with the 'target' param.
  keyBindingsMatchingElement: (target) ->
    @findKeyBindings({target: target[0] ? target})
