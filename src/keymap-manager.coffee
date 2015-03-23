_ = require "underscore-plus"
CSON = require 'season'
Grim = require 'grim'
fs = require 'fs-plus'
{observeCurrentKeyboardLayout} = require 'keyboard-layout'
path = require 'path'
EmitterMixin = require('emissary').Emitter
{File} = require 'pathwatcher'
{Emitter, Disposable, CompositeDisposable} = require 'event-kit'
KeyBinding = require './key-binding'
CommandEvent = require './command-event'
{normalizeKeystrokes, keystrokeForKeyboardEvent, isAtomModifier, keydownEvent} = require './helpers'

Platforms = ['darwin', 'freebsd', 'linux', 'sunos', 'win32']
OtherPlatforms = Platforms.filter (platform) -> platform isnt process.platform

# Extended: Allows commands to be associated with keystrokes in a
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
class KeymapManager
  EmitterMixin.includeInto(this)

  ###
  Section: Class Methods
  ###

  # Public: Create a keydown DOM event for testing purposes.
  #
  # * `key` The key or keyIdentifier of the event. For example, `'a'`, `'1'`,
  #   `'escape'`, `'backspace'`, etc.
  # * `options` (optional) An {Object} containing any of the following:
  #   * `ctrl`   A {Boolean} indicating the ctrl modifier key
  #   * `alt`    A {Boolean} indicating the alt modifier key
  #   * `shift`  A {Boolean} indicating the shift modifier key
  #   * `cmd`    A {Boolean} indicating the cmd modifier key
  #   * `which`  A {Number} indicating `which` value of the event. See
  #     the docs for KeyboardEvent for more information.
  #   * `target` The target element of the event.
  @buildKeydownEvent: (key, options) -> keydownEvent(key, options)

  @keydownEvent: (key, options) ->
    Grim.deprecate("Use .buildKeydownEvent instead.")
    keydownEvent(key, options)

  ###
  Section: Properties
  ###

  partialMatchTimeout: 1000

  defaultTarget: null
  pendingPartialMatches: null
  pendingStateTimeoutHandle: null
  dvorakQwertyWorkaroundEnabled: false

  ###
  Section: Construction and Destruction
  ###

  # Public: Create a new KeymapManager.
  #
  # * `options` An {Object} containing properties to assign to the keymap.  You
  #   can pass custom properties to be used by extension methods. The
  #   following properties are also supported:
  #   * `defaultTarget` This will be used as the target of events whose target
  #     is `document.body` to allow for a catch-all element when nothing is focused.
  constructor: (options={}) ->
    @[key] = value for key, value of options
    @emitter = new Emitter
    @keyBindings = []
    @queuedKeyboardEvents = []
    @queuedKeystrokes = []
    @watchSubscriptions = {}
    @enableDvorakQwertyWorkaroundIfNeeded()

    @testSelectorElement = document.createElement('div')
    @selectorCache = {}

  # Public: Unwatch all watched paths.
  destroy: ->
    @keyboardLayoutSubscription.dispose()
    for filePath, subscription of @watchSubscriptions
      subscription.dispose()

    @testSelectorElement = null
    @selectorCache = null

    return

  enableDvorakQwertyWorkaroundIfNeeded: ->
    @keyboardLayoutSubscription = observeCurrentKeyboardLayout (layoutId) =>
      @dvorakQwertyWorkaroundEnabled = layoutId is 'com.apple.keylayout.DVORAK-QWERTYCMD'

  ###
  Section: Event Subscription
  ###

  # Public: Invoke the given callback when one or more keystrokes completely
  # match a key binding.
  #
  # * `callback` {Function} to be called when keystrokes match a binding.
  #   * `event` {Object} with the following keys:
  #     * `keystrokes` {String} of keystrokes that matched the binding.
  #     * `binding` {KeyBinding} that the keystrokes matched.
  #     * `keyboardEventTarget` DOM element that was the target of the most
  #        recent keyboard event.
  #
  # Returns a {Disposable} on which `.dispose()` can be called to unsubscribe.
  onDidMatchBinding: (callback) ->
    @emitter.on 'did-match-binding', callback

  # Public: Invoke the given callback when one or more keystrokes partially
  # match a binding.
  #
  # * `callback` {Function} to be called when keystrokes partially match a
  #   binding.
  #   * `event` {Object} with the following keys:
  #     * `keystrokes` {String} of keystrokes that matched the binding.
  #     * `partiallyMatchedBindings` {KeyBinding}s that the keystrokes partially
  #       matched.
  #     * `keyboardEventTarget` DOM element that was the target of the most
  #       recent keyboard event.
  #
  # Returns a {Disposable} on which `.dispose()` can be called to unsubscribe.
  onDidPartiallyMatchBindings: (callback) ->
    @emitter.on 'did-partially-match-binding', callback

  # Public: Invoke the given callback when one or more keystrokes fail to match
  # any bindings.
  #
  # * `callback` {Function} to be called when keystrokes fail to match any
  #   bindings.
  #   * `event` {Object} with the following keys:
  #     * `keystrokes` {String} of keystrokes that matched the binding.
  #     * `keyboardEventTarget` DOM element that was the target of the most
  #        recent keyboard event.
  #
  # Returns a {Disposable} on which `.dispose()` can be called to unsubscribe.
  onDidFailToMatchBinding: (callback) ->
    @emitter.on 'did-fail-to-match-binding', callback

  # Invoke the given callback when a keymap file is reloaded.
  #
  # * `callback` {Function} to be called when a keymap file is reloaded.
  #   * `event` {Object} with the following keys:
  #     * `path` {String} representing the path of the reloaded keymap file.
  #
  # Returns a {Disposable} on which `.dispose()` can be called to unsubscribe.
  onDidReloadKeymap: (callback) ->
    @emitter.on 'did-reload-keymap', callback

  # Invoke the given callback when a keymap file is unloaded.
  #
  # * `callback` {Function} to be called when a keymap file is unloaded.
  #   * `event` {Object} with the following keys:
  #     * `path` {String} representing the path of the unloaded keymap file.
  #
  # Returns a {Disposable} on which `.dispose()` can be called to unsubscribe.
  onDidUnloadKeymap: (callback) ->
    @emitter.on 'did-unload-keymap', callback

  # Public: Invoke the given callback when a keymap file not able to be loaded.
  #
  # * `callback` {Function} to be called when a keymap file is unloaded.
  #   * `error` {Object} with the following keys:
  #     * `message` {String} the error message.
  #     * `stack` {String} the error stack trace.
  #
  # Returns a {Disposable} on which `.dispose()` can be called to unsubscribe.
  onDidFailToReadFile: (callback) ->
    @emitter.on 'did-fail-to-read-file', callback

  on: (eventName) ->
    switch eventName
      when 'matched'
        Grim.deprecate("Call KeymapManager::onDidMatchBinding instead")
      when 'matched-partially'
        Grim.deprecate("Call KeymapManager::onDidPartiallyMatchBinding instead")
      when 'match-failed'
        Grim.deprecate("Call KeymapManager::onDidFailToMatchBinding instead")
      when 'reloaded-key-bindings'
        Grim.deprecate("Call KeymapManager::onDidReloadKeymap instead")
      when 'unloaded-key-bindings'
        Grim.deprecate("Call KeymapManager::onDidUnloadKeymap instead")
      else
        Grim.deprecate("Use explicit event subscription methods instead")

    EmitterMixin::on.apply(this, arguments)

  ###
  Section: Adding and Removing Bindings
  ###

  # Public: Add sets of key bindings grouped by CSS selector.
  #
  # * `source` A {String} (usually a path) uniquely identifying the given bindings
  #   so they can be removed later.
  # * `bindings` An {Object} whose top-level keys point at sub-objects mapping
  #   keystroke patterns to commands.
  add: (source, keyBindingsBySelector) ->
    addedKeyBindings = []
    for selector, keyBindings of keyBindingsBySelector
      # Verify selector is valid before registering any bindings
      unless @isValidSelector(selector.replace(/!important/g, ''))
        console.warn("Encountered an invalid selector adding key bindings from '#{source}': '#{selector}'")
        return

      for keystrokes, command of keyBindings
        if normalizedKeystrokes = normalizeKeystrokes(keystrokes)
          keyBinding = new KeyBinding(source, command, normalizedKeystrokes, selector)
          addedKeyBindings.push(keyBinding)
          @keyBindings.push(keyBinding)
        else
          console.warn "Invalid keystroke sequence for binding: `#{keystrokes}: #{command}` in #{source}"

    new Disposable =>
      for keyBinding in addedKeyBindings
        index = @keyBindings.indexOf(keyBinding)
        @keyBindings.splice(index, 1) unless index is -1
      return

  remove: (source) ->
    Grim.deprecate("Call .dispose() on the Disposable returned from KeymapManager::add instead")
    @removeBindingsFromSource(source)

  removeBindingsFromSource: (source) ->
    @keyBindings = @keyBindings.filter (keyBinding) -> keyBinding.source isnt source
    undefined

  ###
  Section: Accessing Bindings
  ###

  # Public: Get all current key bindings.
  #
  # Returns an {Array} of {KeyBinding}s.
  getKeyBindings: ->
    @keyBindings.slice()

  # Public: Get the key bindings for a given command and optional target.
  #
  # * `params` An {Object} whose keys constrain the binding search:
  #   * `keystrokes` A {String} representing one or more keystrokes, such as
  #     'ctrl-x ctrl-s'
  #   * `command` A {String} representing the name of a command, such as
  #     'editor:backspace'
  #   * `target` An optional DOM element constraining the search. If this
  #     parameter is supplied, the call will only return bindings that
  #     can be invoked by a KeyboardEvent originating from the target element.
  #
  # Returns an {Array} of key bindings.
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


  ###
  Section: Managing Keymap Files
  ###

  # Public: Load the key bindings from the given path.
  #
  # * `path` A {String} containing a path to a file or a directory. If the path is
  #   a directory, all files inside it will be loaded.
  # * `options` An {Object} containing the following optional keys:
  #   * `watch` If `true`, the keymap will also reload the file at the given
  #     path whenever it changes. This option cannot be used with directory paths.
  loadKeymap: (bindingsPath, options) ->
    checkIfDirectory = options?.checkIfDirectory ? true
    if checkIfDirectory and fs.isDirectorySync(bindingsPath)
      for filePath in fs.listSync(bindingsPath, ['.cson', '.json'])
        if @filePathMatchesPlatform(filePath)
          @loadKeymap(filePath, checkIfDirectory: false)
    else
      @addKeymap(bindingsPath, @readKeymap(bindingsPath, options?.suppressErrors))
      @watchKeymap(bindingsPath) if options?.watch

    undefined

  # Public: Cause the keymap to reload the key bindings file at the given path
  # whenever it changes.
  #
  # This method doesn't perform the initial load of the key bindings file. If
  # that's what you're looking for, call {::loadKeymap} with `watch: true`.
  #
  # * `path` A {String} containing a path to a file or a directory. If the path is
  #   a directory, all files inside it will be loaded.
  watchKeymap: (filePath) ->
    if not @watchSubscriptions[filePath]? or @watchSubscriptions[filePath].disposed
      file = new File(filePath)
      reloadKeymap = => @reloadKeymap(filePath)
      @watchSubscriptions[filePath] = new CompositeDisposable(
        file.onDidChange(reloadKeymap)
        file.onDidRename(reloadKeymap)
        file.onDidDelete(reloadKeymap)
      )

    undefined

  # Called by the path watcher callback to reload a file at the given path. If
  # we can't read the file cleanly, we don't proceed with the reload.
  reloadKeymap: (filePath) ->
    if fs.isFileSync(filePath)
      if bindings = @readKeymap(filePath, true)
        @removeBindingsFromSource(filePath)
        @addKeymap(filePath, bindings)
        @emit 'reloaded-key-bindings', filePath
        @emitter.emit 'did-reload-keymap', {path: filePath}
    else
      @removeBindingsFromSource(filePath)
      @emit 'unloaded-key-bindings', filePath
      @emitter.emit 'did-unload-keymap', {path: filePath}

  readKeymap: (filePath, suppressErrors) ->
    if suppressErrors
      try
        CSON.readFileSync(filePath)
      catch error
        console.warn("Failed to reload key bindings file: #{filePath}", error.stack ? error)
        @emitter.emit 'did-fail-to-read-file', error
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

  ###
  Section: Managing Keyboard Events
  ###

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
  # If the matching binding's command is 'unset!', the search will continue from
  # the current element's parent.
  #
  # If the matching binding's command is 'abort!', the search will terminate
  # without dispatching a command event.
  #
  # If the event's target is `document.body`, it will be treated as if its
  # target is `.defaultTarget` if that property is assigned on the keymap.
  #
  # * `event` A `KeyboardEvent` of type 'keydown'
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
        exactMatches = @findExactMatches(exactMatchCandidates, currentTarget)
        for exactMatch in exactMatches
          if exactMatch.command is 'native!'
            @clearQueuedKeystrokes()
            return

          if exactMatch.command is 'abort!'
            @clearQueuedKeystrokes()
            event.preventDefault()
            return

          if exactMatch.command is 'unset!'
            break

          foundMatch = true
          break if partialMatches.length > 0
          @clearQueuedKeystrokes()
          @cancelPendingState()
          if @dispatchCommandEvent(exactMatch.command, target, event)
            event = {keystrokes, binding: exactMatch, keyboardEventTarget: target}
            @emit 'matched', event
            @emitter.emit 'did-match-binding', event
            return
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
      event = {keystrokes, partiallyMatchedBindings: partialMatches, keyboardEventTarget: target}
      @emit 'matched-partially', event
      @emitter.emit 'did-partially-match-binding', event
    else
      event = {keystrokes, keyboardEventTarget: target}
      @emit 'match-failed', event
      @emitter.emit 'did-fail-to-match-binding', event
      @terminatePendingState()

  # Public: Translate a keydown event to a keystroke string.
  #
  # * `event` A `KeyboardEvent` of type 'keydown'
  #
  # Returns a {String} describing the keystroke.
  keystrokeForKeyboardEvent: (event) ->
    keystrokeForKeyboardEvent(event, @dvorakQwertyWorkaroundEnabled)

  # Public: Get the number of milliseconds allowed before pending states caused
  # by partial matches of multi-keystroke bindings are terminated.
  #
  # Returns a {Number}
  getPartialMatchTimeout: ->
    @partialMatchTimeout

  ###
  Section: Private
  ###

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
    ignoreKeystrokes = new Set

    while partialMatchCandidates.length > 0 and target? and target isnt document
      partialMatchCandidates = partialMatchCandidates.filter (binding) ->
        if binding.command is 'unset!'
          ignoreKeystrokes.add(binding.keystrokes)
        else if not ignoreKeystrokes.has(binding.keystrokes) and target.webkitMatchesSelector(binding.selector)
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
    return

  # After we match a binding, we call this method to dispatch a custom event
  # based on the binding's command.
  dispatchCommandEvent: (command, target, keyboardEvent) ->
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

    {keyBindingAborted} = commandEvent
    keyboardEvent.preventDefault() unless keyBindingAborted
    not keyBindingAborted

  isValidSelector: (selector) ->
    cachedValue = @selectorCache[selector]
    return cachedValue if cachedValue?

    try
      @testSelectorElement.querySelector(selector)
      @selectorCache[selector] = true
      true
    catch error
      @selectorCache[selector] = false
      false

  # Chromium does not bubble events dispatched on detached targets, which makes
  # testing a pain in the ass. This method simulates bubbling manually.
  simulateBubblingOnDetachedTarget: (target, commandEvent) ->
    Object.defineProperty(commandEvent, 'target', get: -> target)
    Object.defineProperty(commandEvent, 'currentTarget', get: -> currentTarget)
    currentTarget = target
    while currentTarget?
      currentTarget.dispatchEvent(commandEvent)
      break if commandEvent.propagationStopped
      break if currentTarget is window
      currentTarget = currentTarget.parentNode ? window
    return

  # Deprecated: Use {::add} instead.
  addKeymap: (source, bindings) ->
    # Grim.deprecate("Use KeymapManager::add instead.")
    @add(source, bindings)

  # Deprecated: Use {::remove} instead.
  removeKeymap: (source) ->
    # Grim.deprecate("Use KeymapManager::remove instead.")
    @remove(source)

  # Deprecated: Handle a jQuery keyboard event. Use {::handleKeyboardEvent} with
  # a raw keyboard event instead.
  handleKeyEvent: (event) ->
    Grim.deprecate("Use KeymapManager::handleKeyboardEvent instead.")
    originalEvent = event.originalEvent ? event
    Object.defineProperty(originalEvent, 'target', get: -> event.target) unless originalEvent.target?
    @handleKeyboardEvent(originalEvent)
    not originalEvent.defaultPrevented

  # Deprecated: Translate a jQuery keyboard event to a keystroke string. Use
  # {::keystrokeForKeyboardEvent} with a raw KeyboardEvent instead.
  keystrokeStringForEvent: (event) ->
    Grim.deprecate("Use KeymapManager::keystrokeForKeyboardEvent instead.")
    @keystrokeForKeyboardEvent(event.originalEvent ? event)

  # Deprecated: Use {::addKeymap} with a map from selectors to key
  # bindings.
  bindKeys: (source, selector, keyBindings) ->
    Grim.deprecate("Use KeymapManager::addKeymap instead.")
    keyBindingsBySelector = {}
    keyBindingsBySelector[selector] = keyBindings
    @addKeymap(source, keyBindingsBySelector)

  # Deprecated: Use {::findKeyBindings} with the 'command' param.
  keyBindingsForCommand: (command) ->
    Grim.deprecate("Use KeymapManager::findKeyBindings instead.")
    @findKeyBindings({command})

  # Deprecated: Use {::findKeyBindings} with the 'keystrokes' param.
  keyBindingsForKeystroke: (keystroke) ->
    Grim.deprecate("Use KeymapManager::findKeyBindings instead.")
    @findKeyBindings({keystrokes: keystroke})

  # Deprecated: Use {::findKeyBindings} with the 'target' param.
  keyBindingsMatchingElement: (target, keyBindings) ->
    Grim.deprecate("Use KeymapManager::findKeyBindings instead.")
    @findKeyBindings({target: target[0] ? target, keyBindings})

  # Deprecated: Use {::findKeyBindings} with the 'command' and 'target'
  # params
  keyBindingsForCommandMatchingElement: (command, target) ->
    Grim.deprecate("Use KeymapManager::findKeyBindings instead.")
    @findKeyBindings({command, target: target[0] ? target})

  # Deprecated: Use {::findKeyBindings} with the 'keystrokes' and 'target'
  # params
  keyBindingsForKeystrokeMatchingElement: (keystrokes, target) ->
    Grim.deprecate("Use KeymapManager::findKeyBindings instead.")
    @findKeyBindings({keystrokes, target: target[0] ? target})
