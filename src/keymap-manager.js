const CSON = require('season')
const fs = require('fs-plus')

const {isSelectorValid} = require('clear-cut')
const {observeCurrentKeyboardLayout} = require('keyboard-layout')
const path = require('path')
const {File} = require('pathwatcher')
const {Emitter, Disposable, CompositeDisposable} = require('event-kit')
const {KeyBinding, MATCH_TYPES} = require('./key-binding')
const CommandEvent = require('./command-event')
const {
  normalizeKeystrokes,
  keystrokeForKeyboardEvent,
  isBareModifier,
  keydownEvent,
  keyupEvent,
  characterForKeyboardEvent,
  isKeyup
} = require('./helpers')
const PartialKeyupMatcher = require('./partial-keyup-matcher')

const Platforms = ['darwin', 'freebsd', 'linux', 'sunos', 'win32']

const OtherPlatforms = Platforms.filter(function (platform) {
  return platform !== process.platform
})

/*
  Extended: Allows commands to be associated with keystrokes in a
  context-sensitive way. In Atom, you can access a global instance of this
  object via `atom.keymaps`.

  Key bindings are plain JavaScript objects containing **CSS selectors** as
  their top level keys, then **keystroke patterns** mapped to commands.

  ```cson
  '.workspace':
    'ctrl-l': 'package:do-something'
    'ctrl-z': 'package:do-something-else'
  '.mini.editor':
    'enter': 'core:confirm'
  ```

  When a keystroke sequence matches a binding in a given context, a custom DOM
  event with a type based on the command is dispatched on the target of the
  keyboard event.

  To match a keystroke sequence, the keymap starts at the target element for the
  keyboard event. It looks for key bindings associated with selectors that match
  the target element. If multiple match, the most specific is selected. If there
  is a tie in specificity, the most recently added binding wins. If no bindings
  are found for the events target, the search is repeated again for the target's
  parent node and so on recursively until a binding is found or we traverse off
  the top of the document.

  When a binding is found, its command event is always dispatched on the
  original target of the keyboard event, even if the matching element is higher
  up in the DOM. In addition, `.preventDefault()` is called on the keyboard
  event to prevent the browser from taking action. `.preventDefault` is only
  called if a matching binding is found.

  Command event objects have a non-standard method called `.abortKeyBinding()`.
  If your command handler is invoked but you programmatically determine that no
  action can be taken and you want to allow other bindings to be matched, call
  `.abortKeyBinding()` on the event object. An example of where this is useful
  is binding snippet expansion to `tab`. If `snippets:expand` is invoked when
  the cursor does not follow a valid snippet prefix, we abort the binding and
  allow `tab` to be handled by the default handler, which inserts whitespace.

  Multi-keystroke bindings are possible. If a sequence of one or more keystrokes
  *partially* matches a multi-keystroke binding, the keymap enters a pending
  state. The pending state is terminated on the next keystroke, or after
  {::partialMatchTimeout} milliseconds has elapsed. When the pending state is
  terminated via a timeout or a keystroke that leads to no matches, the longest
  ambiguous bindings that caused the pending state are temporarily disabled and
  the previous keystrokes are replayed. If there is ambiguity again during the
  replay, the next longest bindings are disabled and the keystrokes are replayed
  again.
 */
module.exports = class KeymapManager {
  /*
    Section: Class Methods

    Public: Create a keydown DOM event for testing purposes.

    * `key` The key or keyIdentifier of the event. For example, `'a'`, `'1'`,
     `'escape'`, `'backspace'`, etc.
    * `options` (optional) An {Object} containing any of the following:
     * `ctrl`   A {Boolean} indicating the ctrl modifier key
     * `alt`    A {Boolean} indicating the alt modifier key
     * `shift`  A {Boolean} indicating the shift modifier key
     * `cmd`    A {Boolean} indicating the cmd modifier key
     * `which`  A {Number} indicating `which` value of the event. See
       the docs for KeyboardEvent for more information.
     * `target` The target element of the event.
   */
  static buildKeydownEvent (key, options) {
    return keydownEvent(key, options)
  }

  static buildKeyupEvent (key, options) {
    return keyupEvent(key, options)
  }

  /*
    Section: Construction and Destruction

    Public: Create a new KeymapManager.

    * `options` An {Object} containing properties to assign to the keymap.  You
    can pass custom properties to be used by extension methods. The
    following properties are also supported:
    * `defaultTarget` This will be used as the target of events whose target
     is `document.body` to allow for a catch-all element when nothing is focused.
  */
  constructor (options = {}) {
    for (var key in options) {
      this[key] = options[key]
    }

    /*
      Section: Properties
    */
    this.partialMatchTimeout = 1000

    this.defaultTarget = null
    this.pendingPartialMatches = null
    this.pendingStateTimeoutHandle = null
    this.dvorakQwertyWorkaroundEnabled = false

    /*
      Pending matches to bindings that begin with keydowns and end with a subset of matching keyups
    */
    this.pendingKeyupMatcher = new PartialKeyupMatcher()

    this.watchSubscriptions = {}
    this.clear()
    this.enableDvorakQwertyWorkaroundIfNeeded()
  }

  /*
    Public: Clear all registered key bindings and enqueued keystrokes. For use
    in tests.
  */
  clear () {
    this.emitter = new Emitter()
    this.keyBindings = []
    this.queuedKeyboardEvents = []
    this.queuedKeystrokes = []
    this.bindingsToDisable = []
    return this.bindingsToDisable
  }

  /*
    Public: Unwatch all watched paths.
  */
  destroy () {
    this.keyboardLayoutSubscription.dispose()

    for (var key in this.watchSubscriptions) {
      var subscription = this.watchSubscriptions[key]
      subscription.dispose()
    }

    return
  }

  enableDvorakQwertyWorkaroundIfNeeded () {
    this.keyboardLayoutSubscription = observeCurrentKeyboardLayout((layoutId) => {
      this.dvorakQwertyWorkaroundEnabled = (((typeof layoutId !== 'undefined' && layoutId !== null ? layoutId.indexOf('DVORAK-QWERTYCMD') : void 0)) > -1)
      return this.dvorakQwertyWorkaroundEnabled
    })
    return this.keyboardLayoutSubscription
  }

  /*
    Section: Event Subscription

    Public: Invoke the given callback when one or more keystrokes completely
    match a key binding.

    * `callback` {Function} to be called when keystrokes match a binding.
     * `event` {Object} with the following keys:
       * `keystrokes` {String} of keystrokes that matched the binding.
       * `binding` {KeyBinding} that the keystrokes matched.
       * `keyboardEventTarget` DOM element that was the target of the most
          recent keyboard event.

    Returns a {Disposable} on which `.dispose()` can be called to unsubscribe.
  */
  onDidMatchBinding (callback) {
    return this.emitter.on('did-match-binding', callback)
  }

  /*
    Public: Invoke the given callback when one or more keystrokes partially
    match a binding.

    * `callback` {Function} to be called when keystrokes partially match a
      binding.
      * `event` {Object} with the following keys:
        * `keystrokes` {String} of keystrokes that matched the binding.
        * `partiallyMatchedBindings` {KeyBinding}s that the keystrokes partially
          matched.
        * `keyboardEventTarget` DOM element that was the target of the most
          recent keyboard event.

    Returns a {Disposable} on which `.dispose()` can be called to unsubscribe.
  */
  onDidPartiallyMatchBindings (callback) {
    return this.emitter.on('did-partially-match-binding', callback)
  }

  /*
    Public: Invoke the given callback when one or more keystrokes fail to match
    any bindings.

    * `callback` {Function} to be called when keystrokes fail to match any
      bindings.
      * `event` {Object} with the following keys:
        * `keystrokes` {String} of keystrokes that matched the binding.
        * `keyboardEventTarget` DOM element that was the target of the most
           recent keyboard event.

    Returns a {Disposable} on which `.dispose()` can be called to unsubscribe.
  */
  onDidFailToMatchBinding (callback) {
    return this.emitter.on('did-fail-to-match-binding', callback)
  }

  /*
    Invoke the given callback when a keymap file is reloaded.

    * `callback` {Function} to be called when a keymap file is reloaded.
      * `event` {Object} with the following keys:
        * `path` {String} representing the path of the reloaded keymap file.

    Returns a {Disposable} on which `.dispose()` can be called to unsubscribe.
  */
  onDidReloadKeymap (callback) {
    return this.emitter.on('did-reload-keymap', callback)
  }

  /*
    Invoke the given callback when a keymap file is unloaded.

    * `callback` {Function} to be called when a keymap file is unloaded.
      * `event` {Object} with the following keys:
        * `path` {String} representing the path of the unloaded keymap file.

    Returns a {Disposable} on which `.dispose()` can be called to unsubscribe.
  */
  onDidUnloadKeymap (callback) {
    return this.emitter.on('did-unload-keymap', callback)
  }

  /*
    Public: Invoke the given callback when a keymap file not able to be loaded.

    * `callback` {Function} to be called when a keymap file is unloaded.
      * `error` {Object} with the following keys:
        * `message` {String} the error message.
        * `stack` {String} the error stack trace.

    Returns a {Disposable} on which `.dispose()` can be called to unsubscribe.
  */
  onDidFailToReadFile (callback) {
    return this.emitter.on('did-fail-to-read-file', callback)
  }

  /*
    Section: Adding and Removing Bindings

    Public: Add sets of key bindings grouped by CSS selector.

    * `source` A {String} (usually a path) uniquely identifying the given bindings
      so they can be removed later.
    * `bindings` An {Object} whose top-level keys point at sub-objects mapping
      keystroke patterns to commands.
    * `priority` A {Number} used to sort keybindings which have the same
      specificity. Defaults to `0`.
  */
  add (source, keyBindingsBySelector, priority = 0) {
    var keyBinding
    var normalizedKeystrokes
    var ref
    var addedKeyBindings = []

    for (var selector in keyBindingsBySelector) {
      var keyBindings = keyBindingsBySelector[selector]
      // Verify selector is valid before registering any bindings
      if (!isSelectorValid(selector.replace(/!important/g, ''))) {
        console.warn(
          ("Encountered an invalid selector adding key bindings from '" + (source) + "': '" + (selector) + "'")
        )

        return
      }

      for (var keystrokes in keyBindings) {
        var command = keyBindings[keystrokes]
        command = (ref = (command != null ? (typeof command.toString === 'function' ? command.toString() : void 0) : void 0)) != null ? ref : ''

        if (command.length === 0) {
          console.warn(
            ('Empty command for binding: `' + (selector) + '` `' + (keystrokes) + '` in ' + (source))
          )

          return
        }

        normalizedKeystrokes = normalizeKeystrokes(keystrokes)
        if (normalizedKeystrokes) {
          keyBinding = new KeyBinding(source, command, normalizedKeystrokes, selector, priority)
          addedKeyBindings.push(keyBinding)
          this.keyBindings.push(keyBinding)
        } else {
          console.warn(
            ('Invalid keystroke sequence for binding: `' + (keystrokes) + ': ' + (command) + '` in ' + (source))
          )
        }
      }
    }

    return new Disposable(() => {
      for (var keyBinding of addedKeyBindings) {
        var index = this.keyBindings.indexOf(keyBinding)

        if (index !== -1) {
          this.keyBindings.splice(index, 1)
        }
      }

      return
    })
  }

  removeBindingsFromSource (source) {
    this.keyBindings = this.keyBindings.filter(function (keyBinding) {
      return keyBinding.source !== source
    })

    return undefined
  }

  /*
    Section: Accessing Bindings

    Public: Get all current key bindings.

    Returns an {Array} of {KeyBinding}s.
  */
  getKeyBindings () {
    return this.keyBindings.slice()
  }

  /*
    Public: Get the key bindings for a given command and optional target.

    * `params` An {Object} whose keys constrain the binding search:
      * `keystrokes` A {String} representing one or more keystrokes, such as
        'ctrl-x ctrl-s'
      * `command` A {String} representing the name of a command, such as
        'editor:backspace'
      * `target` An optional DOM element constraining the search. If this
        parameter is supplied, the call will only return bindings that
        can be invoked by a KeyboardEvent originating from the target element.

    Returns an {Array} of key bindings.
  */
  findKeyBindings (params = {}) {
    var element
    var candidateBindings

    var {
      keystrokes,
      command,
      target,
      keyBindings
    } = params

    var bindings = keyBindings != null ? keyBindings : this.keyBindings

    if (command != null) {
      bindings = bindings.filter(function (binding) {
        return binding.command === command
      })
    }

    if (keystrokes != null) {
      bindings = bindings.filter(function (binding) {
        return binding.keystrokes === keystrokes
      })
    }

    if (target != null) {
      candidateBindings = bindings
      bindings = []
      element = target

      while (element != null && element !== document) {
        var matchingBindings = candidateBindings.filter(function (binding) {
          return element.webkitMatchesSelector(binding.selector)
        }).sort(function (a, b) {
          return a.compare(b)
        })

        bindings.push(...matchingBindings)
        element = element.parentElement
      }
    }

    return bindings
  }

  /*
    Section: Managing Keymap Files

    Public: Load the key bindings from the given path.

    * `path` A {String} containing a path to a file or a directory. If the path is
      a directory, all files inside it will be loaded.
    * `options` An {Object} containing the following optional keys:
      * `watch` If `true`, the keymap will also reload the file at the given
        path whenever it changes. This option cannot be used with directory paths.
      * `priority` A {Number} used to sort keybindings which have the same
        specificity.
  */
  loadKeymap (bindingsPath, options) {
    var ref
    var checkIfDirectory = (ref = (typeof options !== 'undefined' && options !== null ? options.checkIfDirectory : void 0)) != null ? ref : true

    if (checkIfDirectory && fs.isDirectorySync(bindingsPath)) {
      for (var filePath of fs.listSync(bindingsPath, ['.cson', '.json'])) {
        if (this.filePathMatchesPlatform(filePath)) {
          this.loadKeymap(filePath, {
            checkIfDirectory: false
          })
        }
      }
    } else {
      this.add(bindingsPath, this.readKeymap(
        bindingsPath,
        typeof options !== 'undefined' && options !== null ? options.suppressErrors : void 0
      ), typeof options !== 'undefined' && options !== null ? options.priority : void 0)

      if (typeof options !== 'undefined' && options !== null ? options.watch : void 0) {
        this.watchKeymap(bindingsPath, options)
      }
    }

    return undefined
  }

  /*
    Public: Cause the keymap to reload the key bindings file at the given path
    whenever it changes.

    This method doesn't perform the initial load of the key bindings file. If
    that's what you're looking for, call {::loadKeymap} with `watch: true`.

    * `path` A {String} containing a path to a file or a directory. If the path is
      a directory, all files inside it will be loaded.
    * `options` An {Object} containing the following optional keys:
      * `priority` A {Number} used to sort keybindings which have the same
        specificity.
  */
  watchKeymap (filePath, options) {
    var reloadKeymap
    var file

    if (!(this.watchSubscriptions[filePath] != null) || this.watchSubscriptions[filePath].disposed) {
      file = new File(filePath)

      reloadKeymap = () => {
        return this.reloadKeymap(filePath, options)
      }

      this.watchSubscriptions[filePath] = new CompositeDisposable(
        file.onDidChange(reloadKeymap),
        file.onDidRename(reloadKeymap),
        file.onDidDelete(reloadKeymap)
      )
    }

    return undefined
  }

  /*
    Called by the path watcher callback to reload a file at the given path. If
    we can't read the file cleanly, we don't proceed with the reload.
  */
  reloadKeymap (filePath, options) {
    var bindings

    if (fs.isFileSync(filePath)) {
      bindings = this.readKeymap(filePath, true)

      if (typeof bindings !== 'undefined') {
        this.removeBindingsFromSource(filePath)

        this.add(
          filePath,
          bindings,
          typeof options !== 'undefined' && options !== null ? options.priority : void 0
        )

        return this.emitter.emit('did-reload-keymap', {
          path: filePath
        })
      }
    } else {
      this.removeBindingsFromSource(filePath)

      return this.emitter.emit('did-unload-keymap', {
        path: filePath
      })
    }
  }

  readKeymap (filePath, suppressErrors) {
    if (suppressErrors) {
      try {
        return CSON.readFileSync(filePath, {
          allowDuplicateKeys: false
        })
      } catch (error) {
        var ref

        console.warn(
          ('Failed to reload key bindings file: ' + (filePath)),
          (ref = error.stack) != null ? ref : error
        )

        this.emitter.emit('did-fail-to-read-file', error)
        return undefined
      }
    } else {
      return CSON.readFileSync(filePath, {
        allowDuplicateKeys: false
      })
    }
  }

  /*
    Determine if the given path should be loaded on this platform. If the
    filename has the pattern '<platform>.cson' or 'foo.<platform>.cson' and
    <platform> does not match the current platform, returns false. Otherwise
    returns true.
  */
  filePathMatchesPlatform (filePath) {
    var otherPlatforms = this.getOtherPlatforms()

    for (var component of path.basename(filePath).split('.').slice(0, -1)) {
      if (otherPlatforms.includes(component)) {
        return false
      }
    }

    return true
  }

  /*
    Section: Managing Keyboard Events

    Public: Dispatch a custom event associated with the matching key binding for
    the given `KeyboardEvent` if one can be found.

    If a matching binding is found on the event's target or one of its
    ancestors, `.preventDefault()` is called on the keyboard event and the
    binding's command is emitted as a custom event on the matching element.

    If the matching binding's command is 'native!', the method will terminate
    without calling `.preventDefault()` on the keyboard event, allowing the
    browser to handle it as normal.

    If the matching binding's command is 'unset!', the search will continue from
    the current element's parent.

    If the matching binding's command is 'abort!', the search will terminate
    without dispatching a command event.

    If the event's target is `document.body`, it will be treated as if its
    target is `.defaultTarget` if that property is assigned on the keymap.

    * `event` A `KeyboardEvent` of type 'keydown'
  */
  handleKeyboardEvent (
    event, options = {}) {
    var { replay, disabledBindings } = options
    var enableTimeout
    var allPartialMatchesContainKeyupRemainder
    var eventHandled
    var currentTarget
    var liveMatches
    /*
      Handling keyboard events is complicated and very nuanced. The complexity
      is all due to supporting multi-stroke bindings. An example binding we'll
      use throughout this very long comment:

      'ctrl-a b c': 'my-sweet-command' // This is a binding

      This example means the user can type `ctrl-a` then `b` then `c`, and after
      all of those keys are typed, it will dispatch the `my-sweet-command`
      command.

      The KeymapManager has a couple member variables to deal with multi-stroke
      bindings: `@queuedKeystrokes` and `@queuedKeyboardEvents`. They keep track
      of the keystrokes the user has typed. When populated, the state variables
      look something like:

      @queuedKeystrokes = ['ctrl-a', 'b', 'c']
      @queuedKeyboardEvents = [KeyboardEvent, KeyboardEvent, KeyboardEvent]

      Basically, this `handleKeyboardEvent` function will try to exactly match
      the user's keystrokes to a binding. If it cant match exactly, it looks for
      partial matches. So say, a user typed `ctrl-a` then `b`, but not `c` yet.
      The `ctrl-a b c` binding would be partially matched:

      // The original binding: 'ctrl-a b c': 'my-sweet-command'
      @queuedKeystrokes = ['ctrl-a', 'b'] // The user's keystrokes
      @queuedKeyboardEvents = [KeyboardEvent, KeyboardEvent]

      When it finds partially matching bindings, it will put the KeymapManager
      into a pending state via `enterPendingState` indicating that it is waiting
      for either a timeout or more keystrokes to exactly match the partial
      matches. In our example, it is waiting for the user to type `c` to
      complete the partially matched `ctrl-a b c` binding.

      If a keystroke comes in that either matches a binding exactly, or yields
      no partial matches, we will reset the state variables and exit pending
      mode. If the keystroke yields no partial matches we will call
      `terminatePendingState`. An extension of our last example:

      // Both of these will exit pending state for: 'ctrl-a b c': 'my-sweet-command'
      @queuedKeystrokes = ['ctrl-a', 'b', 'c'] // User typed `c`. Exact match! Dispatch the command and clear state variables. Easy.
      @queuedKeystrokes = ['ctrl-a', 'b', 'd'] // User typed `d`. No hope of matching, terminatePendingState(). Dragons.

      `terminatePendingState` is where things get crazy. Let's pretend the user
      typed 3 total keystrokes: `ctrl-a`, `b`, then `d`. There are no exact
      matches with these keystrokes given the original `'ctrl-a b c'` binding,
      but other bindings might match a subset of the user's typed keystrokes.
      Let's pretend we had more bindings defined:

      // The original binding; no match for ['ctrl-a', 'b', 'd']:
      'ctrl-a b c': 'my-sweet-command'

      // Bindings that all match a subset of ['ctrl-a', 'b', 'd']:
      'ctrl-a': 'ctrl-a-command'
      'b d': 'do-a-bd-deal'
      'd o g': 'wag-the-dog'

      With these example bindings, and the user's `['ctrl-a', 'b', 'd']`
      keystrokes, we should dispatch commands `ctrl-a-command` and
      `do-a-bd-deal`.

      After `['ctrl-a', 'b', 'd']` is typed by the user, `terminatePendingState`
      is called, which will _disable_ the original unmatched `ctrl-a b c`
      binding, empty the keystroke state variables, and _replay_ the key events
      by running them through this `handleKeyboardEvent` function again. The
      replay acts exactly as if a user were typing the keys, but with a disabled
      binding. Because the original binding is disabled, the replayed keystrokes
      will match other, shorter bindings, and in this case, dispatch commands
      for our `ctrl-a` and then our `b d` bindings.

      Because the replay is calling this `handleKeyboardEvent` function again,
      it can get into another pending state, and again call
      `terminatePendingState`. The 2nd call to `terminatePendingState` might
      disable other bindings, and do another replay, which might call this
      function again ... and on and on. It will recurse until the KeymapManager
      is no longer in a pending state with no partial matches from the most
      recent event.

      Godspeed.

      keystroke is the atom keybind syntax, e.g. 'ctrl-a'
    */
    var keystroke = this.keystrokeForKeyboardEvent(event)

    // We dont care about bare modifier keys in the bindings. e.g. `ctrl y` isnt going to work.
    if (event.type === 'keydown' && this.queuedKeystrokes.length > 0 && isBareModifier(keystroke)) {
      event.preventDefault()
      return
    }

    this.queuedKeystrokes.push(keystroke)
    this.queuedKeyboardEvents.push(event)
    var keystrokes = this.queuedKeystrokes.join(' ')

    /*
      If the event's target is document.body, assign it to defaultTarget instead
      to provide a catch-all element when nothing is focused.
    */
    var target = (replay ? document.activeElement : event.target)
    if (event.target === document.body && this.defaultTarget != null) {
      target = this.defaultTarget
    }

    /*
    First screen for any bindings that match the current keystrokes,
    regardless of their current selector. Matching strings is cheaper than
    matching selectors.
    */
    var {
      partialMatchCandidates,
      pendingKeyupMatchCandidates,
      exactMatchCandidates
    } = this.findMatchCandidates(this.queuedKeystrokes, disabledBindings)
    var dispatchedExactMatch = null
    var partialMatches = this.findPartialMatches(partialMatchCandidates, target)

    /*
      If any partial match *was* pending but has now failed to match, add it to
      the list of bindings to disable so we don't attempt to match it again
      during a subsequent event replay by `terminatePendingState`.
    */
    if (this.pendingPartialMatches != null) {
      liveMatches = new Set(partialMatches.concat(exactMatchCandidates))

      for (var binding of this.pendingPartialMatches) {
        if (!liveMatches.has(binding)) {
          this.bindingsToDisable.push(binding)
        }
      }
    }

    var hasPartialMatches = partialMatches.length > 0
    var shouldUsePartialMatches = hasPartialMatches

    if (isKeyup(keystroke)) {
      exactMatchCandidates = exactMatchCandidates.concat(this.pendingKeyupMatcher.getMatches(keystroke))
    }

    /*
      Determine if the current keystrokes match any bindings *exactly*. If we
      do find an exact match, the next step depends on whether we have any
      partial matches. If we have no partial matches, we dispatch the command
      immediately. Otherwise we break and allow ourselves to enter the pending
      state with a timeout.
     */
    if (exactMatchCandidates.length > 0) {
      currentTarget = target
      eventHandled = false

      while (!eventHandled && currentTarget != null && currentTarget !== document) {
        var exactMatches = this.findExactMatches(exactMatchCandidates, currentTarget)

        for (var exactMatchCandidate of exactMatches) {
          if (exactMatchCandidate.command === 'native!') {
            shouldUsePartialMatches = false
            // `break` breaks out of this loop, `eventHandled = true` breaks out of the parent loop
            eventHandled = true
            break
          }

          if (exactMatchCandidate.command === 'abort!') {
            event.preventDefault()
            eventHandled = true
            break
          }

          if (exactMatchCandidate.command === 'unset!') {
            break
          }

          if (hasPartialMatches) {
            /*
              When there is a set of bindings like `'ctrl-y', 'ctrl-y ^ctrl'`,
              and a `ctrl-y` comes in, this will allow the `ctrl-y` command to be
              dispatched without waiting for any other keystrokes.
            */
            allPartialMatchesContainKeyupRemainder = true

            for (var partialMatch of partialMatches) {
              if (pendingKeyupMatchCandidates.indexOf(partialMatch) < 0) {
                allPartialMatchesContainKeyupRemainder = false
                /*
                  We found one partial match with unmatched keydowns.
                  We can stop looking.
                */
                break
              }
            }

            /*
              Don't dispatch this exact match. There are partial matches left
              that have keydowns.
            */
            if (allPartialMatchesContainKeyupRemainder === false) {
              break
            }
          } else {
            shouldUsePartialMatches = false
          }

          if (this.dispatchCommandEvent(exactMatchCandidate.command, target, event)) {
            dispatchedExactMatch = exactMatchCandidate
            eventHandled = true

            for (var pendingKeyupMatch of pendingKeyupMatchCandidates) {
              this.pendingKeyupMatcher.addPendingMatch(pendingKeyupMatch)
            }

            break
          }
        }

        currentTarget = currentTarget.parentElement
      }
    }

    // Emit events. These are done on their own for clarity.

    if (dispatchedExactMatch != null) {
      this.emitter.emit('did-match-binding', {
        keystrokes: keystrokes,
        eventType: event.type,
        binding: dispatchedExactMatch,
        keyboardEventTarget: target
      })
    } else if (hasPartialMatches && shouldUsePartialMatches) {
      event.preventDefault()

      this.emitter.emit('did-partially-match-binding', {
        keystrokes: keystrokes,
        eventType: event.type,
        partiallyMatchedBindings: partialMatches,
        keyboardEventTarget: target
      })
    } else if (!(dispatchedExactMatch != null) && !hasPartialMatches) {
      this.emitter.emit('did-fail-to-match-binding', {
        keystrokes: keystrokes,
        eventType: event.type,
        keyboardEventTarget: target
      })
      /*
        Some of the queued keyboard events might have inserted characters had
        we not prevented their default action. If we're replaying a keystroke
        whose default action was prevented and no binding is matched, we'll
        simulate the text input event that was previously prevented to insert
        the missing characters.
      */
      if (event.defaultPrevented && event.type === 'keydown') {
        this.simulateTextInput(event)
      }
    }

    // Manage the keystroke queue state. State is updated separately for clarity.

    if (dispatchedExactMatch) {
      this.bindingsToDisable.push(dispatchedExactMatch)
    }

    if (hasPartialMatches && shouldUsePartialMatches) {
      enableTimeout = (this.pendingStateTimeoutHandle != null || dispatchedExactMatch != null || characterForKeyboardEvent(this.queuedKeyboardEvents[0]) != null)

      if (replay) {
        enableTimeout = false
      }

      return this.enterPendingState(partialMatches, enableTimeout)
    } else if (!(dispatchedExactMatch != null) && !hasPartialMatches && this.pendingPartialMatches != null) {
      /*
        There are partial matches from a previous event, but none from this
        event. This means the current event has removed any hope that the queued
        key events will ever match any binding. So we will clear the state and
        start over after replaying the events in `terminatePendingState`.
      */
      return this.terminatePendingState()
    } else {
      return this.clearQueuedKeystrokes()
    }
  }

  /*
    Public: Translate a keydown event to a keystroke string.

    * `event` A `KeyboardEvent` of type 'keydown'

    Returns a {String} describing the keystroke.
  */
  keystrokeForKeyboardEvent (event) {
    return keystrokeForKeyboardEvent(event, this.dvorakQwertyWorkaroundEnabled)
  }

  /*
    Public: Get the number of milliseconds allowed before pending states caused
    by partial matches of multi-keystroke bindings are terminated.

    Returns a {Number}
 */
  getPartialMatchTimeout () {
    return this.partialMatchTimeout
  }

  /*
  Section: Private
  */

  simulateTextInput (keydownEvent) {
    var textInputEvent
    var character = characterForKeyboardEvent(keydownEvent, this.dvorakQwertyWorkaroundEnabled)

    if (character) {
      textInputEvent = document.createEvent('TextEvent')
      textInputEvent.initTextEvent('textInput', true, true, window, character)
      return keydownEvent.path[0].dispatchEvent(textInputEvent)
    }
  }

  // For testing purposes
  getOtherPlatforms () {
    return OtherPlatforms
  }

  /*
    Finds all key bindings whose keystrokes match the given keystrokes.
    Returns both partial and exact matches.
  */
  findMatchCandidates (keystrokeArray, disabledBindings) {
    var doesMatch
    var partialMatchCandidates = []
    var exactMatchCandidates = []
    var pendingKeyupMatchCandidates = []
    var disabledBindingSet = new Set(disabledBindings)

    for (var binding of this.keyBindings) {
      if (!disabledBindingSet.has(binding)) {
        doesMatch = binding.matchesKeystrokes(keystrokeArray)

        if (doesMatch === MATCH_TYPES.EXACT) {
          exactMatchCandidates.push(binding)
        } else if (doesMatch === MATCH_TYPES.PARTIAL) {
          partialMatchCandidates.push(binding)
        } else if (doesMatch === MATCH_TYPES.PENDING_KEYUP) {
          partialMatchCandidates.push(binding)
          pendingKeyupMatchCandidates.push(binding)
        }
      }
    }

    return {
      partialMatchCandidates: partialMatchCandidates,
      pendingKeyupMatchCandidates: pendingKeyupMatchCandidates,
      exactMatchCandidates: exactMatchCandidates
    }
  }

  /*
    Determine which of the given bindings have selectors matching the target or
    one of its ancestors. This is used by {::handleKeyboardEvent} to determine
    if there are any partial matches for the keyboard event.
  */
  findPartialMatches (partialMatchCandidates, target) {
    var partialMatches = []
    var ignoreKeystrokes = new Set()

    partialMatchCandidates.forEach(function (binding) {
      if (binding.command === 'unset!') {
        return ignoreKeystrokes.add(binding.keystrokes)
      }
    })

    while (partialMatchCandidates.length > 0 && (typeof target !== 'undefined' && target !== null) && target !== document) {
      partialMatchCandidates = partialMatchCandidates.filter(function (binding) {
        if (!ignoreKeystrokes.has(binding.keystrokes) && target.webkitMatchesSelector(binding.selector)) {
          partialMatches.push(binding)
          return false
        } else {
          return true
        }
      })

      target = target.parentElement
    }

    return partialMatches.sort(function (a, b) {
      return b.keystrokeCount - a.keystrokeCount
    })
  }

  /*
    Find the matching bindings among the given candidates for the given target,
    ordered by specificity. Does not traverse up the target's ancestors. This is
    used by {::handleKeyboardEvent} to find a matching binding when there are no
    partially-matching bindings.
 */
  findExactMatches (exactMatchCandidates, target) {
    return exactMatchCandidates.filter(function (binding) {
      return target.webkitMatchesSelector(binding.selector)
    }).sort(function (a, b) {
      return a.compare(b)
    })
  }

  clearQueuedKeystrokes () {
    this.queuedKeyboardEvents = []
    this.queuedKeystrokes = []
    this.bindingsToDisable = []
    return this.bindingsToDisable
  }

  enterPendingState (pendingPartialMatches, enableTimeout) {
    if (this.pendingStateTimeoutHandle != null) {
      this.cancelPendingState()
    }

    this.pendingPartialMatches = pendingPartialMatches

    if (enableTimeout) {
      this.pendingStateTimeoutHandle = setTimeout(this.terminatePendingState.bind(this, true), this.partialMatchTimeout)
      return this.pendingStateTimeoutHandle
    }
  }

  cancelPendingState () {
    clearTimeout(this.pendingStateTimeoutHandle)
    this.pendingStateTimeoutHandle = null
    this.pendingPartialMatches = null
    return this.pendingPartialMatches
  }

  /*
    This is called by {::handleKeyboardEvent} when no matching bindings are
    found for the currently queued keystrokes or by the pending state timeout.
    It disables the longest of the pending partially matching bindings, then
    replays the queued keyboard events to allow any bindings with shorter
    keystroke sequences to be matched unambiguously.

    Note that replaying events has a recursive behavior. Replaying will set
    member state (e.g. @queuedKeyboardEvents) just like real events, and will
    likely result in another call to this function. The replay process will
    potentially replay the events (or a subset of events) several times, while
    disabling bindings here and there. See any spec that handles multiple
    keystrokes failures to match a binding.
  */
  terminatePendingState (fromTimeout) {
    var bindingsToDisable = this.pendingPartialMatches.concat(this.bindingsToDisable)
    var eventsToReplay = this.queuedKeyboardEvents
    this.cancelPendingState()
    this.clearQueuedKeystrokes()

    var keyEventOptions = {
      replay: true,
      disabledBindings: bindingsToDisable
    }

    for (var event of eventsToReplay) {
      keyEventOptions.disabledBindings = bindingsToDisable
      this.handleKeyboardEvent(event, keyEventOptions)

      // We can safely re-enable the bindings when we no longer have any partial matches
      if (bindingsToDisable != null && !(this.pendingPartialMatches != null)) {
        bindingsToDisable = null
      }
    }

    if (fromTimeout && this.pendingPartialMatches != null) {
      this.terminatePendingState(true)
    }

    return
  }

  /*
    After we match a binding, we call this method to dispatch a custom event
    based on the binding's command.
  */
  dispatchCommandEvent (command, target, keyboardEvent) {
    /*
      Here we use prototype chain injection to add CommandEvent methods to this
      custom event to support aborting key bindings and simulated bubbling for
      detached targets.
     */
    var commandEvent = new CustomEvent(command, {
      bubbles: true,
      cancelable: true
    })
    Object.setPrototypeOf(commandEvent, CommandEvent.prototype)
    commandEvent.originalEvent = keyboardEvent

    if (document.contains(target)) {
      target.dispatchEvent(commandEvent)
    } else {
      this.simulateBubblingOnDetachedTarget(target, commandEvent)
    }

    var {keyBindingAborted} = commandEvent
    if (!keyBindingAborted) keyboardEvent.preventDefault()
    return !keyBindingAborted
  }

  /*
    Chromium does not bubble events dispatched on detached targets, which makes
    testing a pain in the ass. This method simulates bubbling manually.
  */
  simulateBubblingOnDetachedTarget (target, commandEvent) {
    var ref
    Object.defineProperty(commandEvent, 'target', {
      get: function () {
        return target
      }
    })
    Object.defineProperty(commandEvent, 'currentTarget', {
      get: function () {
        return currentTarget
      }
    })
    var currentTarget = target
    while (currentTarget != null) {
      currentTarget.dispatchEvent(commandEvent)
      if (commandEvent.propagationStopped) break
      if (currentTarget === window) break
      currentTarget = (ref = currentTarget.parentNode) != null ? ref : window
    }
    return
  }
}
