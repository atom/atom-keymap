CSON = require 'season'
fs = require 'fs-plus'
path = require 'path'
{Emitter} = require 'emissary'
{File} = require 'pathwatcher'
KeyBinding = require './key-binding'
CommandEvent = require './command-event'
{keystrokeForKeyboardEvent, isAtomModifier, keydownEvent} = require './helpers'

Platforms = ['darwin', 'freebsd', 'linux', 'sunos', 'win32']
OtherPlatforms = Platforms.filter (platform) -> platform isnt process.platform

# Public: Allows commands to be associated with keystrokes in a
# context-sensitive way. In Atom, you can access a global instance of this
# object via `atom.keymap`.
#
# Key bindings are plain JavaScript objects containing **CSS selectors** as
# their top level keys, then **keystroke patterns** mapped to commands.
#
# ```cson
# '.workspace':
#   'ctrl-l': 'package:do-something'
#   'ctrl-z': 'package:do-something-else'
# '.mini.editor':
#   'enter': 'core:confirm'
# ```
#
# When a keystroke sequence matches a binding in a given context, a custom DOM
# event with a type based on the command is dispatched on the target of the
# keyboard event.
#
# To match a keystroke sequence, the keymap starts at the target element for the
# keyboard event. It looks for key bindings associated with selectors that match
# the target element. If multiple match, the most specific is selected. If there
# is a tie in specificity, the most recently added binding wins. If no bindings
# are found for the events target, the search is repeated again for the target's
# parent node and so on recursively until a binding is found or we traverse off
# the top of the document.
#
# When a binding is found, its command event is always dispatched on the
# original target of the keyboard event, even if the matching element is higher
# up in the DOM. In addition, `.preventDefault()` is called on the keyboard
# event to prevent the browser from taking action. `.preventDefault` is only
# called if a matching binding is found.
#
# Command event objects have a non-standard method called `.abortKeyBinding()`.
# If your command handler is invoked but you programmatically determine that no
# action can be taken and you want to allow other bindings to be matched, call
# `.abortKeyBinding()` on the event object. An example of where this is useful
# is binding snippet expansion to `tab`. If `snippets:expand` is invoked when
# the cursor does not follow a valid snippet prefix, we abort the binding and
# allow `tab` to be handled by the default handler, which inserts whitespace.
#
# Multi-keystroke bindings are possible. If a sequence of one or more keystrokes
# *partially* matches a multi-keystroke binding, the keymap enters a pending
# state. The pending state is terminated on the next keystroke, or after
# {::partialMatchTimeout} milliseconds has elapsed. When the pending state is
# terminated via a timeout or a keystroke that leads to no matches, the longest
# ambiguous bindings that caused the pending state are temporarily disabled and
# the previous keystrokes are replayed. If there is ambiguity again during the
# replay, the next longest bindings are disabled and the keystrokes are replayed
# again.
module.exports =
class Keymap
  Emitter.includeInto(this)

  # Public: Create a keydown DOM event for testing purposes.
  #
  # key - The key or keyIdentifier of the event. For example, 'a', '1',
  #   'escape', 'backspace', etc.
  # options - An {Object} containing any of the following:
  #   :ctrl - A {Boolean} indicating the ctrl modifier key
  #   :alt - A {Boolean} indicating the alt modifier key
  #   :shift - A {Boolean} indicating the shift modifier key
  #   :cmd - A {Boolean} indicating the cmd modifier key
  #   :which - A {Number} indicating `which` value of the event. See
  #      the docs for KeyboardEvent for more information.
  #   :target - The target element of the event.
  @keydownEvent: (key, options) -> keydownEvent(key, options)

  # Public: The number of milliseconds allowed before pending states caused
  # by partial matches of multi-keystroke bindings are terminated.
  partialMatchTimeout: 1000

  defaultTarget: null
  pendingPartialMatches: null
  pendingStateTimeoutHandle: null

  # Public:
  #
  # options - An {Object} containing properties to assign to the keymap: You can
  #   pass custom properties to be used by extension methods. The following
  #   properties are also supported:
  #   :defaultTarget - This will be used as the target of events whose target
  #     is `document.body` to allow for a catch-all element when nothing is
  #     focused
  constructor: (options={}) ->
    @[key] = value for key, value of options
    @keyBindings = []
    @queuedKeyboardEvents = []
    @queuedKeystrokes = []
    @watchSubscriptions = {}

  # Public: Unwatch all watched paths.
  destroy: ->
    for filePath, subscription of @watchSubscriptions
      subscription.off()

  # Public: Get all current key bindings.
  #
  # Returns an {Array} of {KeyBinding}s.
  getKeyBindings: ->
    @keyBindings.slice()

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
        document.body.webkitMatchesSelector(selector.replace(/!important/g, ''))
      catch e
        console.warn("Encountered an invalid selector adding key bindings from '#{source}': '#{selector}'")
        return

      for keystroke, command of keyBindings
        keyBinding = new KeyBinding(source, command, keystroke, selector)
        @keyBindings.push(keyBinding)

  # Public: Load the key bindings from the given path.
  #
  # path - A {String} containing a path to a file or a directory. If the path is
  #   a directory, all files inside it will be loaded.
  # options - An {Object} containing the following optional keys:
  #   :watch - If `true`, the keymap will also reload the file at the given path
  #     whenever it changes. This option cannot be used with directory paths.
  loadKeyBindings: (bindingsPath, options) ->
    checkIfDirectory = options?.checkIfDirectory ? true
    if checkIfDirectory and fs.isDirectorySync(bindingsPath)
      for filePath in fs.listSync(bindingsPath, ['.cson', '.json'])
        if @filePathMatchesPlatform(filePath)
          @loadKeyBindings(filePath, checkIfDirectory: false)
    else
      @addKeyBindings(bindingsPath, @readKeyBindings(bindingsPath, options?.suppressErrors))
      @watchKeyBindings(bindingsPath) if options?.watch

  # Public: Cause the keymap to reload the key bindings file at the given path
  # whenever it changes.
  #
  # This method doesn't perform the initial load of the key bindings file. If
  # that's what you're looking for, call {::loadKeyBindings} with `watch: true`.
  watchKeyBindings: (filePath) ->
    unless @watchSubscriptions[filePath]?.cancelled is false
      @watchSubscriptions[filePath] =
        new File(filePath).on 'contents-changed moved removed', =>
          @reloadKeyBindings(filePath)

  # Public: Remove the key bindings added with {::addKeyBindings} or
  # {::loadKeyBindings}.
  #
  # source - A {String} representing the `source` in a previous call to
  #   {::addKeyBindings} or the path in {::loadKeyBindings}.
  removeKeyBindings: (source) ->
    @keyBindings = @keyBindings.filter (keyBinding) -> keyBinding.source isnt source

  # Public: Dispatch a custom event associated with the matching key binding for
  # the given `KeyboardEvent` if one can be found.
  #
  # If a matching binding is found on the event's target or one of its
  # ancestors, `.preventDefault()` is called on the keyboard event and the
  # binding's command is emitted as a custom event on the matching element.
  #
  # If the matching binding's command is 'native!', the method will terminate
  # without calling `.preventDefault()` on the keyboard event, allowing the
  # browser to handle it as normal.
  #
  # If the event's target is `document.body`, it will be treated as if its
  # target is `.defaultTarget` if that property is assigned on the keymap.
  handleKeyboardEvent: (event, replaying) ->
    keystroke = @keystrokeForKeyboardEvent(event)

    if @queuedKeystrokes.length > 0 and isAtomModifier(keystroke)
      event.preventDefault()
      return

    @queuedKeyboardEvents.push(event)
    @queuedKeystrokes.push(keystroke)
    keystrokes = @queuedKeystrokes.join(' ')

    # If the event's target is document.body, assign it to defaultTarget instead
    # to provide a catch-all element when nothing is focused.
    target = event.target
    target = @defaultTarget if event.target is document.body and @defaultTarget?

    # First screen for any bindings that match the current keystrokes,
    # regardless of their current selector. Matching strings is cheaper than
    # matching selectors.
    {partialMatchCandidates, exactMatchCandidates} = @findMatchCandidates(keystrokes)
    partialMatches = @findPartialMatches(partialMatchCandidates, target)

    # Determine if the current keystrokes match any bindings *exactly*. If we
    # do find and exact match, the next step depends on whether we have any
    # partial matches. If we have no partial matches, we dispatch the command
    # immediately. Otherwise we break and allow ourselves to enter the pending
    # state with a timeout.
    if exactMatchCandidates.length > 0
      currentTarget = target
      while currentTarget? and currentTarget isnt document
        for exactMatch in @findExactMatches(exactMatchCandidates, currentTarget)
          return if exactMatch.command is 'native!'

          foundMatch = true
          break if partialMatches.length > 0
          @clearQueuedKeystrokes()
          @cancelPendingState()
          return if @dispatchCommandEvent(exactMatch.command, target, event)
        currentTarget = currentTarget.parentElement

    # If we're at this point in the method, we either found no matches for the
    # currently queued keystrokes or we found a match, but we need to enter a
    # pending state due to partial matches. We only enable the timeout of the
    # pending state if we found an exact match on this or a previously queued
    # keystroke.
    if partialMatches.length > 0
      event.preventDefault()
      enableTimeout = foundMatch ? @pendingStateTimeoutHandle?
      @enterPendingState(partialMatches, enableTimeout)
    else
      @terminatePendingState()

  # Public: Get the key bindings for a given command and optional target.
  #
  # params - An {Object} whose keys constrain the binding search:
  #   :command - A {String} representing one or more keystrokes, such as
  #     'ctrl-x ctrl-s'
  #   :command - A {String} representing the name of a command, such as
  #     'editor:backspace'
  #   :target - An optional DOM element constraining the search. If this
  #     parameter is supplied, the call will only return bindings that can be
  #     invoked by a KeyboardEvent originating from the target element.
  findKeyBindings: (params={}) ->
    {keystrokes, command, target, keyBindings} = params

    bindings = keyBindings ? @keyBindings

    if command?
      bindings = bindings.filter (binding) -> binding.command is command

    if keystrokes?
      bindings = bindings.filter (binding) -> binding.keystrokes is keystrokes

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

  # Called by the path watcher callback to reload a file at the given path. If
  # we can't read the file cleanly, we don't proceed with the reload.
  reloadKeyBindings: (filePath) ->
    if fs.isFileSync(filePath)
      if bindings = @readKeyBindings(filePath, true)
        @removeKeyBindings(filePath)
        @addKeyBindings(filePath, bindings)
        @emit 'reloaded-key-bindings', filePath
    else
      @removeKeyBindings(filePath)
      @emit 'unloaded-key-bindings', filePath

  readKeyBindings: (filePath, suppressErrors) ->
    if suppressErrors
      try
        CSON.readFileSync(filePath)
      catch error
        console.warn("Failed to reload key bindings file: #{filePath}", error.stack ? error)
        undefined
    else
      CSON.readFileSync(filePath)

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

  # Finds all key bindings whose keystrokes match the given keystrokes. Returns
  # both partial and exact matches.
  findMatchCandidates: (keystrokes) ->
    partialMatchCandidates = []
    exactMatchCandidates = []

    keystrokesWithSpace = keystrokes + ' '

    for binding in @keyBindings when binding.enabled
      if binding.keystrokes is keystrokes
        exactMatchCandidates.push(binding)
      else if binding.keystrokes.indexOf(keystrokesWithSpace) is 0
        partialMatchCandidates.push(binding)
    {partialMatchCandidates, exactMatchCandidates}

  # Determine which of the given bindings have selectors matching the target or
  # one of its ancestors. This is used by {::handleKeyboardEvent} to determine
  # if there are any partial matches for the keyboard event.
  findPartialMatches: (partialMatchCandidates, target) ->
    partialMatches = []
    while partialMatchCandidates.length > 0 and target? and target isnt document
      partialMatchCandidates = partialMatchCandidates.filter (binding) ->
        if target.webkitMatchesSelector(binding.selector)
          partialMatches.push(binding)
          false
        else
          true
      target = target.parentElement
    partialMatches.sort (a, b) -> b.keystrokeCount - a.keystrokeCount

  # Find the matching bindings among the given candidates for the given target,
  # ordered by specificity. Does not traverse up the target's ancestors. This is
  # used by {::handleKeyboardEvent} to find a matching binding when there are no
  # partially-matching bindings.
  findExactMatches: (exactMatchCandidates, target) ->
    exactMatches = exactMatchCandidates
      .filter (binding) -> target.webkitMatchesSelector(binding.selector)
      .sort (a, b) -> a.compare(b)

  clearQueuedKeystrokes: ->
    @queuedKeyboardEvents = []
    @queuedKeystrokes = []

  enterPendingState: (pendingPartialMatches, enableTimeout) ->
    @cancelPendingState() if @pendingStateTimeoutHandle?
    @pendingPartialMatches = pendingPartialMatches
    if enableTimeout
      @pendingStateTimeoutHandle = setTimeout(@terminatePendingState.bind(this), @partialMatchTimeout)

  cancelPendingState: ->
    clearTimeout(@pendingStateTimeoutHandle)
    @pendingStateTimeoutHandle = null
    @pendingPartialMatches = null

  # This is called by {::handleKeyboardEvent} when no matching bindings are
  # found for the currently queued keystrokes or by the pending state timeout.
  # It disables the longest of the pending partially matching bindings, then
  # replays the queued keyboard events to allow any bindings with shorter
  # keystroke sequences to be matched unambiguously.
  terminatePendingState: ->
    unless @pendingPartialMatches?
      @clearQueuedKeystrokes()
      return

    bindingsToDisable = @pendingPartialMatches
    eventsToReplay = @queuedKeyboardEvents

    @cancelPendingState()
    @clearQueuedKeystrokes()

    binding.enabled = false for binding in bindingsToDisable
    @handleKeyboardEvent(event, true) for event in eventsToReplay
    binding.enabled = true for binding in bindingsToDisable

  # After we match a binding, we call this method to dispatch a custom event
  # based on the binding's command.
  dispatchCommandEvent: (command, target, keyboardEvent) ->
    keyboardEvent.preventDefault()

    # Here we use prototype chain injection to add CommandEvent methods to this
    # custom event to support aborting key bindings and simulated bubbling for
    # detached targets.
    commandEvent = new CustomEvent(command, bubbles: true, cancelable: true)
    commandEvent.__proto__ = CommandEvent::
    commandEvent.originalEvent = keyboardEvent

    if document.contains(target)
      target.dispatchEvent(commandEvent)
    else
      @simulateBubblingOnDetachedTarget(target, commandEvent)

    not commandEvent.keyBindingAborted

  # Chromium does not bubble events dispatched on detached targets, which makes
  # testing a pain in the ass. This method simulates bubbling manually.
  simulateBubblingOnDetachedTarget: (target, commandEvent) ->
    Object.defineProperty(commandEvent, 'target', get: -> target)
    Object.defineProperty(commandEvent, 'currentTarget', get: -> currentTarget)
    currentTarget = target
    while currentTarget?
      currentTarget.dispatchEvent(commandEvent)
      break if commandEvent.propagationStopped
      currentTarget = currentTarget.parentElement

  # Public: Translate a keydown event to a keystroke string.
  #
  # event - A `KeyboardEvent` of type 'keydown'
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
    originalEvent = event.originalEvent ? event
    Object.defineProperty(originalEvent, 'target', get: -> event.target) unless originalEvent.target?
    @handleKeyboardEvent(originalEvent)
    not originalEvent.defaultPrevented

  # Deprecated: Translate a jQuery keyboard event to a keystroke string. Use
  # {::keystrokeForKeyboardEvent} with a raw KeyboardEvent instead.
  keystrokeStringForEvent: (event) ->
    @keystrokeForKeyboardEvent(event.originalEvent ? event)

  # Deprecated: Use {::addKeyBindings} with a map from selectors to key
  # bindings.
  bindKeys: (source, selector, keyBindings) ->
    keyBindingsBySelector = {}
    keyBindingsBySelector[selector] = keyBindings
    @addKeyBindings(source, keyBindingsBySelector)

  # Deprecated: Use {::findKeyBindings} with the 'command' param.
  keyBindingsForCommand: (command) ->
    @findKeyBindings({command})

  # Deprecated: Use {::findKeyBindings} with the 'keystrokes' param.
  keyBindingsForKeystroke: (keystroke) ->
    @findKeyBindings({keystrokes: keystroke})

  # Deprecated: Use {::findKeyBindings} with the 'target' param.
  keyBindingsMatchingElement: (target, keyBindings) ->
    @findKeyBindings({target: target[0] ? target, keyBindings})

  # Deprecated: Use {::findKeyBindings} with the 'command' and 'target'
  # params
  keyBindingsForCommandMatchingElement: (command, target) ->
    @findKeyBindings({command, target: target[0] ? target})

  # Deprecated: Use {::findKeyBindings} with the 'keystrokes' and 'target'
  # params
  keyBindingsForKeystrokeMatchingElement: (keystrokes, target) ->
    @findKeyBindings({keystrokes, target: target[0] ? target})
