{$$} = require 'space-pencil'
debounce = require 'debounce'
fs = require 'fs-plus'
path = require 'path'
temp = require 'temp'
KeyboardLayout = require('keyboard-layout')
KeymapManager = require '../src/keymap-manager'
{appendContent, stub, getFakeClock, mockProcessPlatform, buildKeydownEvent, buildKeyupEvent} = require './helpers/helpers'

describe "KeymapManager", ->
  keymapManager = null

  beforeEach ->
    mockProcessPlatform('darwin')
    keymapManager = new KeymapManager

  afterEach ->
    keymapManager.destroy()

  describe "::handleKeyboardEvent(event)", ->
    describe "when the keystroke matches no bindings", ->
      it "does not prevent the event's default action", ->
        event = buildKeydownEvent(key: 'q')
        keymapManager.handleKeyboardEvent(event)
        assert(not event.defaultPrevented)
    describe "when the keystroke matches one binding on any particular element", ->
      [events, elementA, elementB] = []

      beforeEach ->
        elementA = appendContent $$ ->
          @div class: 'a', ->
            @div class: 'b c'
        elementB = elementA.firstChild

        events = []
        elementA.addEventListener 'x-command', (e) -> events.push(e)
        elementA.addEventListener 'y-command', (e) -> events.push(e)

        keymapManager.add "test",
          ".a":
            "ctrl-x": "x-command"
            "ctrl-y": "y-command"
          ".c":
            "ctrl-y": "z-command"
          ".b":
            "ctrl-y": "y-command"

      it "dispatches the matching binding's command event on the keyboard event's target", ->
        keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'y', ctrlKey: true, target: elementB))
        assert.equal(events.length, 1)
        assert.equal(events[0].type, 'y-command')
        assert.equal(events[0].target, elementB)

        events = []
        keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'x', ctrlKey: true, target: elementB))
        assert.equal(events.length, 1)
        assert.equal(events[0].type, 'x-command')
        assert.equal(events[0].target, elementB)

      it "prevents the default action", ->
        event = buildKeydownEvent(key: 'y', ctrlKey: true, target: elementB)
        keymapManager.handleKeyboardEvent(event)
        assert(event.defaultPrevented)

      describe "if .abortKeyBinding() is called on the command event", ->
        it "proceeds directly to the next matching binding and does not prevent the keyboard event's default action", ->
          elementB.addEventListener 'y-command', (e) -> events.push(e); e.abortKeyBinding()
          elementB.addEventListener 'y-command', (e) -> events.push(e) # should never be called
          elementB.addEventListener 'z-command', (e) -> events.push(e); e.abortKeyBinding()

          event = buildKeydownEvent(key: 'y', ctrlKey: true, target: elementB)
          keymapManager.handleKeyboardEvent(event)
          assert(not event.defaultPrevented)

          assert.equal(events.length, 3)
          assert.equal(events[0].type, 'y-command')
          assert.equal(events[0].target, elementB)
          assert.equal(events[1].type, 'z-command')
          assert.equal(events[1].target, elementB)
          assert.equal(events[2].type, 'y-command')
          assert.equal(events[2].target, elementB)

      describe "if the keyboard event's target is document.body", ->
        it "starts matching keybindings at the .defaultTarget", ->
          keymapManager.defaultTarget = elementA
          keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'y', ctrlKey: true, target: document.body))
          assert.equal(events.length, 1)
          assert.equal(events[0].type, 'y-command')
          assert.equal(events[0].target, elementA)

      describe "if the matching binding's command is 'native!'", ->
        it "terminates without preventing the browser's default action", ->
          elementA.addEventListener 'native!', (e) -> events.push(e)
          keymapManager.add "test",
            ".b":
              "ctrl-y": "native!"

          event = buildKeydownEvent(key: 'y', ctrlKey: true, target: elementB)
          keymapManager.handleKeyboardEvent(event)
          assert.deepEqual(events, [])
          assert(not event.defaultPrevented)

      describe "if the matching binding's command is 'unset!'", ->
        it "continues searching for a matching binding on the parent element", ->
          elementA.addEventListener 'unset!', (e) -> events.push(e)
          keymapManager.add "test",
            ".a":
              "ctrl-y": "x-command"
            ".b":
              "ctrl-y": "unset!"

          event = buildKeydownEvent(key: 'y', ctrlKey: true, target: elementB)
          keymapManager.handleKeyboardEvent(event)
          assert.equal(events.length, 1)
          assert.equal(events[0].type, 'x-command')
          assert.equal(event.defaultPrevented, true)

      describe "if the matching binding's command is 'unset!' and there is another match", ->
        it "immediately matches the other match", ->
          elementA.addEventListener 'unset!', (e) -> events.push(e)
          keymapManager.add "test",
            ".a":
              "ctrl-y": "x-command"
              "ctrl-y ctrl-y": "unset!"
          event = buildKeydownEvent(key: 'y', ctrlKey: true, target: elementA)
          keymapManager.handleKeyboardEvent(event)
          assert.equal(events.length, 1)
          assert.equal(events[0].type, 'x-command')

      describe "if the matching binding's command is 'abort!'", ->
        it "stops searching for a matching binding immediately and emits no command event", ->
          elementA.addEventListener 'abort!', (e) -> events.push(e)
          keymapManager.add "test",
            ".a":
              "ctrl-y": "y-command"
              "ctrl-x": "x-command"
            ".b":
              "ctrl-y": "abort!"

          event = buildKeydownEvent(key: 'y', ctrlKey: true, target: elementB)
          keymapManager.handleKeyboardEvent(event)
          assert.equal(events.length, 0)
          assert(event.defaultPrevented)

          keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'x', ctrlKey: true, target: elementB))
          assert.equal(events.length, 1)

    describe "when the keystroke matches multiple bindings on the same element", ->
      [elementA, elementB, events] = []

      beforeEach ->
        elementA = appendContent $$ ->
          @div class: 'a', ->
            @div class: 'b c d'
        elementB = elementA.firstChild

        events = []
        elementA.addEventListener 'command-1', ((e) -> events.push(e)), false
        elementA.addEventListener 'command-2', ((e) -> events.push(e)), false
        elementA.addEventListener 'command-3', ((e) -> events.push(e)), false

      describe "when the bindings have the same priority", ->
        describe "when the bindings have selectors with different specificity", ->
          beforeEach ->
            keymapManager.add "test",
              ".b.c":
                "ctrl-x": "command-1"
              ".b":
                "ctrl-x": "command-2"

          it "dispatches the command associated with the most specific binding", ->
            keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'x', ctrlKey: true, target: elementB))
            assert.equal(events.length, 1)
            assert.equal(events[0].type, 'command-1')
            assert.equal(events[0].target, elementB)

        describe "when the bindings have selectors with the same specificity", ->
          it "dispatches the command associated with the most recently added binding", ->
            keymapManager.add "test",
              ".b.c":
                "ctrl-x": "command-1"
              ".c.d":
                "ctrl-x": "command-2"

            keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'x', ctrlKey: true, target: elementB))

            assert.equal(events.length, 1)
            assert.equal(events[0].type, 'command-2')
            assert.equal(events[0].target, elementB)

      describe "when bindings have different priorities", ->
        it "dispatches the command associated with the binding which has the highest priority", ->
          keymapManager.add "keybindings-with-super-priority", {".c": {"ctrl-x": "command-1"}}, 2
          keymapManager.add "keybindings-with-priority", {".b.c.d": {"ctrl-x": "command-2"}}, 1
          keymapManager.add "normal-keybindings", {".b.c.d": {"ctrl-x": "command-3"}}, 0

          keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'x', ctrlKey: true, target: elementB))

          assert.equal(events.length, 1)
          assert.equal(events[0].type, 'command-1')
          assert.equal(events[0].target, elementB)

    describe "when the keystroke partially matches bindings", ->
      [workspace, editor, events] = []

      beforeEach ->
        workspace = appendContent $$ ->
          @div class: 'workspace', ->
            @div class: 'editor'
        editor = workspace.firstChild

        keymapManager.add 'test',
          '.workspace':
            'd o g': 'dog'
            'd p': 'dp'
            'v i v a': 'viva!'
            'v i v': 'viv'
            'shift shift-S x': 'shift-then-s'
          '.editor': 'v': 'enter-visual-mode'
          '.editor.visual-mode': 'i w': 'select-inside-word'

        events = []
        editor.addEventListener 'textInput', (event) -> events.push("input:#{event.data}")
        workspace.addEventListener 'dog', -> events.push('dog')
        workspace.addEventListener 'dp', -> events.push('dp')
        workspace.addEventListener 'viva!', -> events.push('viva!')
        workspace.addEventListener 'viv', -> events.push('viv')
        workspace.addEventListener 'select-inside-word', -> events.push('select-inside-word')
        workspace.addEventListener 'enter-visual-mode', -> events.push('enter-visual-mode'); editor.classList.add('visual-mode')

      describe "when subsequent keystrokes yield an exact match", ->
        it "dispatches the command associated with the matched multi-keystroke binding", ->
          keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'v', target: editor))
          keymapManager.handleKeyboardEvent(buildKeyupEvent(key: 'v', target: editor))
          keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'i', target: editor))
          keymapManager.handleKeyboardEvent(buildKeyupEvent(key: 'i', target: editor))
          keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'v', target: editor))
          keymapManager.handleKeyboardEvent(buildKeyupEvent(key: 'v', target: editor))
          keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'a', target: editor))
          keymapManager.handleKeyboardEvent(buildKeyupEvent(key: 'a', target: editor))
          assert.deepEqual(events, ['viva!'])

      describe "when subsequent keystrokes yield no matches", ->
        it "disables the bindings with the longest keystroke sequences and replays the queued keystrokes", ->
          keymapManager.handleKeyboardEvent(vEvent = buildKeydownEvent(key: 'v', target: editor))
          keymapManager.handleKeyboardEvent(iEvent = buildKeydownEvent(key: 'i', target: editor))
          keymapManager.handleKeyboardEvent(wEvent = buildKeydownEvent(key: 'w', target: editor))
          assert.equal(vEvent.defaultPrevented, true)
          assert.equal(iEvent.defaultPrevented, true)
          assert.equal(wEvent.defaultPrevented, true)
          assert.deepEqual(events, ['enter-visual-mode', 'select-inside-word'])

          events = []
          keymapManager.handleKeyboardEvent(vEvent = buildKeydownEvent(key: 'v', target: editor))
          keymapManager.handleKeyboardEvent(iEvent = buildKeydownEvent(key: 'i', target: editor))
          keymapManager.handleKeyboardEvent(kEvent = buildKeydownEvent(key: 'k', target: editor))
          assert.equal(vEvent.defaultPrevented, true)
          assert.equal(iEvent.defaultPrevented, true)
          assert.equal(kEvent.defaultPrevented, false)
          assert.deepEqual(events, ['enter-visual-mode', 'input:i'])
          # FIXME
          # expect(clearTimeout).toHaveBeenCalled()

        it "dispatches a text-input event for any replayed keyboard events that would have inserted characters", ->
          keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'd', target: editor))
          keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'o', target: editor))
          keymapManager.handleKeyboardEvent(lastEvent = buildKeydownEvent(key: 'q', target: editor))

          assert.deepEqual(events, ['input:d', 'input:o'])
          assert(not lastEvent.defaultPrevented)

          events = []
          keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'Shift', target: editor))
          keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'S', target: editor, shiftKey: true))
          keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'y', target: editor))
          assert.deepEqual(events, ['input:S'])

      describe "when the currently queued keystrokes exactly match at least one binding", ->
        it "disables partially-matching bindings and replays the queued keystrokes if the ::partialMatchTimeout expires", ->
          keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'v', target: editor))
          assert.deepEqual(events, [])
          getFakeClock().tick(keymapManager.getPartialMatchTimeout())
          assert.deepEqual(events, ['enter-visual-mode'])

          events = []
          keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'v', target: editor))
          keymapManager.handleKeyboardEvent(buildKeyupEvent(key: 'v', target: editor))
          keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'i', target: editor))
          keymapManager.handleKeyboardEvent(buildKeyupEvent(key: 'i', target: editor))
          assert.deepEqual(events, [])
          getFakeClock().tick(keymapManager.getPartialMatchTimeout())
          assert.deepEqual(events, ['enter-visual-mode', 'input:i'])

          events = []
          keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'v', target: editor))
          keymapManager.handleKeyboardEvent(buildKeyupEvent(key: 'v', target: editor))
          keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'i', target: editor))
          keymapManager.handleKeyboardEvent(buildKeyupEvent(key: 'i', target: editor))
          keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'v', target: editor))
          assert.deepEqual(events, [])
          getFakeClock().tick(keymapManager.getPartialMatchTimeout())
          assert.deepEqual(events, ['viv'])

        it "does not enter a pending state or prevent the default action if the matching binding's command is 'native!'", ->
          keymapManager.add 'test', '.workspace': 'v': 'native!'
          event = buildKeydownEvent(key: 'v', target: editor)
          keymapManager.handleKeyboardEvent(event)
          assert(not event.defaultPrevented)
          getFakeClock().next()
          assert.equal(keymapManager.queuedKeyboardEvents.length, 0)

      describe "when the first queued keystroke corresponds to a character insertion", ->
        it "disables partially-matching bindings and replays the queued keystrokes if the ::partialMatchTimeout expires", ->
          keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'd', target: editor))
          keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'o', target: editor))
          getFakeClock().tick(keymapManager.getPartialMatchTimeout())

          assert.deepEqual(events, ['input:d', 'input:o'])

      describe "when the currently queued keystrokes don't exactly match any bindings", ->
        it "never times out of the pending state", ->
          keymapManager.add 'test',
            '.workspace':
              'ctrl-d o g': 'control-dog'

          workspace.addEventListener 'control-dog', -> events.push('control-dog')

          keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'd', ctrlKey: true, target: editor))
          keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'o', target: editor))

          getFakeClock().tick(keymapManager.getPartialMatchTimeout())
          getFakeClock().tick(keymapManager.getPartialMatchTimeout())

          assert.deepEqual(events, [])
          keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'g', target: editor))
          assert.deepEqual(events, ['control-dog'])

      describe "when the partially matching bindings all map to the 'unset!' directive", ->
        it "ignores the 'unset!' bindings and invokes the command associated with the matching binding as normal", ->
          keymapManager.add 'test-2',
            '.workspace':
              'v i v a': 'unset!'
              'v i v': 'unset!'

          keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'v', target: editor))

          assert.deepEqual(events, ['enter-visual-mode'])

      describe "when a subsequent keystroke begins a new match of an already pending binding", ->
        it "recognizes the match", ->
          keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'd', target: editor))
          keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'o', target: editor))
          keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'd', target: editor))
          keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'o', target: editor))
          keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'g', target: editor))

          assert.deepEqual(events, ['input:d', 'input:o', 'dog'])

    describe "when the binding specifies a keyup handler", ->
      [events, elementA] = []

      beforeEach ->
        elementA = appendContent $$ ->
          @div class: 'a'

        events = []
        elementA.addEventListener 'y-command', (e) -> events.push('y-keydown')
        elementA.addEventListener 'y-command-ctrl-up', (e) -> events.push('y-ctrl-keyup')
        elementA.addEventListener 'x-command-ctrl-up', (e) -> events.push('x-ctrl-keyup')
        elementA.addEventListener 'y-command-y-up-ctrl-up', (e) -> events.push('y-up-ctrl-keyup')
        elementA.addEventListener 'abc-secret-code-command', (e) -> events.push('abc-secret-code')
        elementA.addEventListener 'z-command-d-e-f', (e) -> events.push('z-keydown-d-e-f')

        keymapManager.add "test",
          ".a":
            "ctrl-y": "y-command"
            "ctrl-y ^ctrl": "y-command-ctrl-up"
            "ctrl-x ^ctrl": "x-command-ctrl-up"
            "ctrl-y ^y ^ctrl": "y-command-y-up-ctrl-up"
            "a b c ^b ^a ^c": "abc-secret-code-command"
            "ctrl-z d e f": "z-command-d-e-f"

      it "dispatches the command for a binding containing only keydown events immediately even when there is a corresponding multi-stroke binding that contains only other keyup events", ->
        keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'y', ctrlKey: true, target: elementA))
        assert.deepEqual(events, ['y-keydown'])

      it "dispatches the command when a matching keystroke precedes it", ->
        keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'y', ctrlKey: true, target: elementA))
        assert.deepEqual(events, ['y-keydown'])
        keymapManager.handleKeyboardEvent(buildKeyupEvent(key: 'y', ctrlKey: true, metaKey: true, shiftKey: true, altKey: true, target: elementA))
        assert.deepEqual(events, ['y-keydown'])
        keymapManager.handleKeyboardEvent(buildKeyupEvent(key: 'Control', target: elementA))
        getFakeClock().tick(keymapManager.getPartialMatchTimeout())
        assert.deepEqual(events, ['y-keydown', 'y-up-ctrl-keyup'])

      it "dispatches the command when the keyup comes after the partial match timeout", ->
        keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'y', ctrlKey: true, target: elementA))
        assert.deepEqual(events, ['y-keydown'])
        keymapManager.handleKeyboardEvent(buildKeyupEvent(key: 'y', ctrlKey: true, cmd: true, shift: true, alt: true, target: elementA))
        assert.deepEqual(events, ['y-keydown'])
        getFakeClock().tick(keymapManager.getPartialMatchTimeout())
        keymapManager.handleKeyboardEvent(buildKeyupEvent(key: 'ctrl', target: elementA))
        assert.deepEqual(events, ['y-keydown', 'y-up-ctrl-keyup'])

      it "dispatches the command multiple times when multiple keydown events for the binding come in before the binding with a keyup handler", ->
        keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'y', ctrlKey: true, target: elementA))
        assert.deepEqual(events, ['y-keydown'])
        keymapManager.handleKeyboardEvent(buildKeyupEvent(key: 'y', ctrlKey: true, target: elementA))
        assert.deepEqual(events, ['y-keydown'])
        keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'y', ctrlKey: true, target: elementA))
        assert.deepEqual(events, ['y-keydown', 'y-keydown'])
        getFakeClock().tick(keymapManager.getPartialMatchTimeout())
        assert.deepEqual(events, ['y-keydown', 'y-keydown'])

      it "dispatches the command when the modifier is lifted before the character", ->
        keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'y', ctrlKey: true, target: elementA))
        assert.deepEqual(events, ['y-keydown'])
        keymapManager.handleKeyboardEvent(buildKeyupEvent(key: 'Control', target: elementA))
        assert.deepEqual(events, ['y-keydown', 'y-ctrl-keyup'])
        getFakeClock().tick(keymapManager.getPartialMatchTimeout())
        assert.deepEqual(events, ['y-keydown', 'y-ctrl-keyup'])

      it "dispatches the command when extra user-generated keyup events are not specified in the binding", ->
        keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'x', ctrlKey: true, target: elementA))
        keymapManager.handleKeyboardEvent(buildKeyupEvent(key: 'x', ctrlKey: true, target: elementA)) # not specified in binding
        keymapManager.handleKeyboardEvent(buildKeyupEvent(key: 'Control', target: elementA))
        getFakeClock().tick(keymapManager.getPartialMatchTimeout())
        assert.deepEqual(events, ['x-ctrl-keyup'])

      it "dispatches the command when extra user-generated keydown events not specified in the binding occur between keydown and keyup", ->
        keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'y', ctrlKey: true, target: elementA))
        assert.deepEqual(events, ['y-keydown'])
        keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'j', ctrlKey: true, target: elementA)) # not specified in binding
        assert.deepEqual(events, ['y-keydown'])
        keymapManager.handleKeyboardEvent(buildKeyupEvent(key: 'Control', target: elementA))
        getFakeClock().tick(keymapManager.getPartialMatchTimeout())
        assert.deepEqual(events, ['y-keydown', 'y-ctrl-keyup'])

      it "does _not_ dispatch the command when extra user-generated keydown events not specified in the binding occur between keydowns", ->
        keymapManager.handleKeyboardEvent(buildKeydownEvent('z', ctrl: true, target: elementA))
        keymapManager.handleKeyboardEvent(buildKeyupEvent('ctrl', target: elementA))
        keymapManager.handleKeyboardEvent(buildKeyupEvent('ctrl', target: elementA))
        keymapManager.handleKeyboardEvent(buildKeydownEvent('z', target: elementA)) # not specified in binding
        keymapManager.handleKeyboardEvent(buildKeydownEvent('d', target: elementA))
        keymapManager.handleKeyboardEvent(buildKeydownEvent('e', target: elementA))
        keymapManager.handleKeyboardEvent(buildKeydownEvent('f', target: elementA))
        assert.deepEqual(events, [])

      it "dispatches the command when multiple keyup keystrokes are specified", ->
        keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'a', target: elementA))
        keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'b', target: elementA))
        keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'c', target: elementA))
        keymapManager.handleKeyboardEvent(buildKeyupEvent(key: 'a', target: elementA))
        keymapManager.handleKeyboardEvent(buildKeyupEvent(key: 'b', target: elementA))
        keymapManager.handleKeyboardEvent(buildKeyupEvent(key: 'c', target: elementA))
        getFakeClock().tick(keymapManager.getPartialMatchTimeout())
        assert.deepEqual(events, [])

        keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'a', target: elementA))
        keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'b', target: elementA))
        keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'c', target: elementA))
        keymapManager.handleKeyboardEvent(buildKeyupEvent(key: 'b', target: elementA))
        keymapManager.handleKeyboardEvent(buildKeyupEvent(key: 'a', target: elementA))
        keymapManager.handleKeyboardEvent(buildKeyupEvent(key: 'c', target: elementA))
        getFakeClock().tick(keymapManager.getPartialMatchTimeout())
        assert.deepEqual(events, ['abc-secret-code'])

    it "only counts entire keystrokes when checking for partial matches", ->
      element = $$ -> @div class: 'a'
      keymapManager.add 'test',
        '.a':
          'ctrl-alt-a': 'command-a'
          'ctrl-a': 'command-b'
      events = []
      element.addEventListener 'command-a', -> events.push('command-a')
      element.addEventListener 'command-b', -> events.push('command-b')

      # Should *only* match ctrl-a, not ctrl-alt-a (can't just use a textual prefix match)
      keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'a', ctrlKey: true, target: element))
      assert.deepEqual(events, ['command-b'])

    it "does not enqueue keydown events consisting only of modifier keys", ->
      element = $$ -> @div class: 'a'
      keymapManager.add 'test', '.a': 'ctrl-a ctrl-alt-b': 'command'
      events = []
      element.addEventListener 'command', -> events.push('command')

      # Simulate keydown events for the modifier key being pressed on its own
      # prior to the key it is modifying.
      keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'Control', ctrlKey: true, target: element))
      keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'a', ctrlKey: true, target: element))
      keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'Control', ctrlKey: true, target: element))
      keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'Alt', ctrlKey: true, target: element))
      keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'b', ctrlKey: true, altKey: true, target: element))

      assert.deepEqual(events, ['command'])

    it "allows solo modifier-keys to be bound", ->
      element = $$ -> @div class: 'a'
      keymapManager.add 'test', '.a': 'ctrl': 'command'
      events = []
      element.addEventListener 'command', -> events.push('command')

      keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'Control', target: element))
      assert.deepEqual(events, ['command'])

    it "simulates bubbling if the target is detached", ->
      elementA = $$ ->
        @div class: 'a', ->
          @div class: 'b', ->
            @div class: 'c'
      elementB = elementA.firstChild
      elementC = elementB.firstChild

      keymapManager.add 'test', '.c': 'x': 'command'

      events = []
      elementA.addEventListener 'command', -> events.push('a')
      elementB.addEventListener 'command', (e) ->
        events.push('b1')
        e.stopImmediatePropagation()
      elementB.addEventListener 'command', (e) ->
        events.push('b2')
        assert.equal(e.target, elementC)
        assert.equal(e.currentTarget, elementB)
      elementC.addEventListener 'command', (e) ->
        events.push('c')
        assert.equal(e.target, elementC)
        assert.equal(e.currentTarget, elementC)

      keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'x', target: elementC))

      assert.deepEqual(events, ['c', 'b1'])

  describe "::add(source, bindings)", ->
    it "normalizes keystrokes containing capitalized alphabetic characters", ->
      keymapManager.add 'test', '*': 'ctrl-shift-l': 'a'
      keymapManager.add 'test', '*': 'ctrl-shift-L': 'b'
      keymapManager.add 'test', '*': 'ctrl-L': 'c'
      assert.equal(keymapManager.findKeyBindings(command: 'a')[0].keystrokes, 'ctrl-shift-L')
      assert.equal(keymapManager.findKeyBindings(command: 'b')[0].keystrokes, 'ctrl-shift-L')
      assert.equal(keymapManager.findKeyBindings(command: 'c')[0].keystrokes, 'ctrl-shift-L')

    it "normalizes the order of modifier keys based on the Apple interface guidelines", ->
      keymapManager.add 'test', '*': 'alt-cmd-ctrl-shift-l': 'a'
      keymapManager.add 'test', '*': 'shift-ctrl-l': 'b'
      keymapManager.add 'test', '*': 'alt-ctrl-l': 'c'
      keymapManager.add 'test', '*': 'ctrl-alt--': 'd'

      assert.equal(keymapManager.findKeyBindings(command: 'a')[0].keystrokes, 'ctrl-alt-shift-cmd-L')
      assert.equal(keymapManager.findKeyBindings(command: 'b')[0].keystrokes, 'ctrl-shift-L')
      assert.equal(keymapManager.findKeyBindings(command: 'c')[0].keystrokes, 'ctrl-alt-l')
      assert.equal(keymapManager.findKeyBindings(command: 'd')[0].keystrokes, 'ctrl-alt--')

    it "rejects bindings with unknown modifier keys and logs a warning to the console", ->
      stub(console, 'warn')
      keymapManager.add 'test', '*': 'meta-shift-A': 'a'
      assert.equal(console.warn.callCount, 1)

      event = buildKeydownEvent(key: 'A', shiftKey: true, target: document.body)
      keymapManager.handleKeyboardEvent(event)
      assert.equal(event.defaultPrevented, false)

    it "rejects bindings with an invalid selector and logs a warning to the console", ->
      stub(console, 'warn')
      assert.equal(keymapManager.add('test', '<>': 'shift-a': 'a'), undefined)
      assert.equal(console.warn.callCount, 1)

      event = buildKeydownEvent(key: 'A', shiftKey: true, target: document.body)
      keymapManager.handleKeyboardEvent(event)
      assert(not event.defaultPrevented)

    it "ignores bindings with an invalid selector when throwOnInvalidSelector is false", ->
      stub(console, 'warn')
      assert.notEqual(keymapManager.add('test', {'<>': 'shift-a': 'a'}, 0, false), undefined)
      assert.equal(console.warn.callCount, 0)

    it "rejects bindings with an empty command and logs a warning to the console", ->
      stub(console, 'warn')
      assert.equal(keymapManager.add('test', 'body': 'shift-a': ''), undefined)
      assert.equal(console.warn.callCount, 1)

      event = buildKeydownEvent(key: 'A', shiftKey: true, target: document.body)
      keymapManager.handleKeyboardEvent(event)
      assert(not event.defaultPrevented)

    it "rejects bindings without a command and logs a warning to the console", ->
      stub(console, 'warn')
      assert.equal(keymapManager.add('test', 'body': 'shift-a': null), undefined)
      assert.equal(console.warn.callCount, 1)

      event = buildKeydownEvent(key: 'A', shiftKey: true, target: document.body)
      keymapManager.handleKeyboardEvent(event)
      assert(not event.defaultPrevented)

    it "rejects bindings with a non object command", ->
      stub(console, 'warn')
      assert.equal(keymapManager.add('test', 'body': 'my-sweet-command:that-is-evil'), undefined)
      assert.equal(console.warn.callCount, 1)

      event = buildKeydownEvent(key: '0', target: document.body)
      keymapManager.handleKeyboardEvent(event)
      assert(not event.defaultPrevented)

    it "returns a disposable allowing the added bindings to be removed", ->
      disposable1 = keymapManager.add 'foo',
        '.a':
          'ctrl-a': 'x'
        '.b':
          'ctrl-b': 'y'

      disposable2 = keymapManager.add 'bar',
        '.c':
          'ctrl-c': 'z'

      assert.equal(keymapManager.findKeyBindings(command: 'x').length, 1)
      assert.equal(keymapManager.findKeyBindings(command: 'y').length, 1)
      assert.equal(keymapManager.findKeyBindings(command: 'z').length, 1)

      disposable2.dispose()

      assert.equal(keymapManager.findKeyBindings(command: 'x').length, 1)
      assert.equal(keymapManager.findKeyBindings(command: 'y').length, 1)
      assert.equal(keymapManager.findKeyBindings(command: 'z').length, 0)

  describe "::keystrokeForKeyboardEvent(event)", ->
    describe "when no extra modifiers are pressed", ->
      it "returns a string that identifies the unmodified keystroke", ->
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'a'})), 'a')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'A', shiftKey: true})), 'shift-A')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: '['})), '[')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: '*', shiftKey: true})), '*')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'ArrowLeft'})), 'left')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'Backspace'})), 'backspace')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'Delete'})), 'delete')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'PageUp'})), 'pageup')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: ' ', code: 'Space'})), 'space')

    describe "when a modifier key is combined with a non-modifier key", ->
      it "returns a string that identifies the modified keystroke", ->
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'a', altKey: true})), 'alt-a')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: '[', metaKey: true})), 'cmd-[')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: '*', ctrlKey: true, shiftKey: true})), 'ctrl-*')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'ArrowLeft', ctrlKey: true, altKey: true, metaKey: true})), 'ctrl-alt-cmd-left')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'A', shiftKey: true})), 'shift-A')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'A', ctrlKey: true, shiftKey: true})), 'ctrl-shift-A')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: '{', shiftKey: true})), '{')

    describe "when the KeyboardEvent.key is a capital letter due to caps lock, but shift is not pressed", ->
      it "converts the letter to lower case", ->
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'A', shiftKey: false})), 'a')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'A', shiftKey: false, altKey: true})), 'alt-a')

    describe "when the KeyboardEvent.key is a lower-case letter due to caps lock + shift", ->
      it "converts the letter to upper case and honors the shift key", ->
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'a', shiftKey: true})), 'shift-A')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'a', shiftKey: true, altKey: true})), 'alt-shift-A')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'a', shiftKey: true, ctrlKey: true})), 'ctrl-shift-A')

    describe "when the KeyboardEvent.key is 'Delete' but KeyboardEvent.code is 'Backspace' due to pressing ctrl-delete with numlock enabled on Windows", ->
      it "translates as ctrl-backspace instead of ctrl-delete", ->
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'Delete', code: 'Backspace', ctrlKey: true})), 'ctrl-backspace')

    describe "when the KeyboardEvent.key is '' but the KeyboardEvent.code is 'NumpadDecimal' and getModifierState('NumLock') returns false", ->
      it "translates as delete to work around a Chrome bug on Linux", ->
        mockProcessPlatform('linux')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: '.', code: 'NumpadDecimal', modifierState: {NumLock: true}})), '.')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: '', code: 'NumpadDecimal', modifierState: {NumLock: false}})), 'delete')

    describe "when numlock is on", ->
      it "translates numpad digits using KeyboardEvent.code", ->
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: '0', code: 'Numpad0', modifierState: {NumLock: true}})), 'numpad0')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: '1', code: 'Numpad1', modifierState: {NumLock: true}})), 'numpad1')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: '2', code: 'Numpad2', modifierState: {NumLock: true}})), 'numpad2')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: '3', code: 'Numpad3', modifierState: {NumLock: true}})), 'numpad3')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: '4', code: 'Numpad4', modifierState: {NumLock: true}})), 'numpad4')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: '5', code: 'Numpad5', modifierState: {NumLock: true}})), 'numpad5')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: '6', code: 'Numpad6', modifierState: {NumLock: true}})), 'numpad6')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: '7', code: 'Numpad7', modifierState: {NumLock: true}})), 'numpad7')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: '8', code: 'Numpad8', modifierState: {NumLock: true}})), 'numpad8')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: '9', code: 'Numpad9', modifierState: {NumLock: true}})), 'numpad9')

    describe "when numlock is off", ->
      it "doesn't translate numpad digits using KeyboardEvent.code", ->
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'Insert', code: 'Numpad0', modifierState: {NumLock: false}})), 'insert')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'End', code: 'Numpad1', modifierState: {NumLock: false}})), 'end')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'ArrowDown', code: 'Numpad2', modifierState: {NumLock: false}})), 'down')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'PageDown', code: 'Numpad3', modifierState: {NumLock: false}})), 'pagedown')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'ArrowLeft', code: 'Numpad4', modifierState: {NumLock: false}})), 'left')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'Clear', code: 'Numpad5', modifierState: {NumLock: false}})), 'clear')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'ArrowRight', code: 'Numpad6', modifierState: {NumLock: false}})), 'right')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'Home', code: 'Numpad7', modifierState: {NumLock: false}})), 'home')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'ArrowUp', code: 'Numpad8', modifierState: {NumLock: false}})), 'up')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'PageUp', code: 'Numpad9', modifierState: {NumLock: false}})), 'pageup')

    describe "when the Dvorak QWERTY-⌘ layout is in use on macOS", ->
      it "uses the US layout equivalent when the command key is held down", ->
        mockProcessPlatform('darwin')
        stub(KeyboardLayout, 'getCurrentKeymap', -> require('./helpers/keymaps/mac-dvorak-qwerty-cmd'))
        stub(KeyboardLayout, 'getCurrentKeyboardLayout', -> 'com.apple.keylayout.DVORAK-QWERTYCMD')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'l', code: 'KeyP', altKey: true})), 'alt-l')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'l', code: 'KeyP', ctrlKey: true, altKey: true})), 'ctrl-alt-l')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'l', code: 'KeyP', metaKey: true})), 'cmd-p')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'L', code: 'KeyP', metaKey: true, shiftKey: true})), 'shift-cmd-P')

    describe "when the current system keymap cannot be obtained on macOS", ->
      it "does not throw exceptions and just takes the current key value", ->
        mockProcessPlatform('darwin')
        stub(KeyboardLayout, 'getCurrentKeymap', -> null)
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: '@', code: 'KeyG', modifierState: {AltGraph: true}})), '@')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'Dead', code: 'KeyU', modifierState: {AltGraph: true}})), 'alt-dead')

    describe "international layouts", ->
      currentKeymap = null

      beforeEach ->
        currentKeymap = null
        stub(KeyboardLayout, 'getCurrentKeymap', -> currentKeymap)

      it "allows ASCII characters (<= 127) to be typed via an option modifier on macOS", ->
        mockProcessPlatform('darwin')

        currentKeymap = require('./helpers/keymaps/mac-swiss-german')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: '@', code: 'KeyG', altKey: true})), '@')
        # Does not use alt variant characters outside of basic ASCII range
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: '‚', code: 'KeyG', altKey: true, shiftKey: true})), 'alt-shift-G')
        # Does not use alt variant character if ctrl modifier is used
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: '@', code: 'KeyG', ctrlKey: true, altKey: true})), 'ctrl-alt-g')

      it "allows ASCII characters (<= 127) to be typed via the ctrl-alt- modifiers on Windows", ->
        mockProcessPlatform('win32')

        currentKeymap = require('./helpers/keymaps/windows-swiss-german')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: '@', code: 'Digit2', ctrlKey: true, altKey: true})), '@')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: '°', code: 'Digit4', ctrlKey: true, altKey: true})), 'ctrl-alt-4')

        currentKeymap = require('./helpers/keymaps/windows-us-international')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: '¢', code: 'KeyC', ctrlKey: true, altKey: true, shiftKey: true})), 'ctrl-alt-shift-C')

      it "allows arbitrary characters to be typed via an altgraph modifier on Linux", ->
        mockProcessPlatform('linux')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: '@', modifierState: {AltGraph: true}})), '@')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: '€', modifierState: {AltGraph: true}})), '€')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'Ë', shiftKey: true, modifierState: {AltGraph: true}})), 'shift-Ë')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'g', altKey: true, altGraphKey: false})), 'alt-g')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'e', altKey: true, altGraphKey: false})), 'alt-e')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'E', altKey: true, shiftKey: true, altGraphKey: false})), 'alt-shift-E')

      it "falls back to the non-alt key if other modifiers are combined with ALtGraph on Linux", ->
        mockProcessPlatform('linux')
        currentKeymap = require('./helpers/keymaps/linux-swiss-german')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: '@', code: 'KeyG', ctrlKey: true, modifierState: {AltGraph: true}})), 'ctrl-alt-g')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: '@', code: 'KeyG', metaKey: true, modifierState: {AltGraph: true}})), 'alt-cmd-g')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: '@', code: 'KeyG', altKey: true, modifierState: {AltGraph: true}})), 'alt-g')

      it "resolves events with a key value of Unknown and a code of IntlRo to '/' (this occurs on a Brazillian Portuguese keyboard layout on Mint Linux)", ->
        mockProcessPlatform('linux')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'Unidentified', code: 'IntlRo', ctrlKey: true})), 'ctrl-/')

      it "on non-Latin keyboards, converts keystrokes with modifiers to U.S. layout equivalent characters", ->
        currentKeymap = require('./helpers/keymaps/mac-greek')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'δ', code: 'KeyD'})), 'd')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'Δ', code: 'KeyD', shiftKey: true})), 'shift-D')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: '÷', altKey: true, code: 'KeyD'})), 'alt-d')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'δ', code: 'KeyD', metaKey: true})), 'cmd-d')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'Δ', code: 'KeyD', metaKey: true, shiftKey: true})), 'shift-cmd-D')

        # If *any* key on the keyboard is non-Latin, even characters that *are* Latin remap to the U.S. equivalent character for the physical key
        currentKeymap = require('./helpers/keymaps/mac-russian-pc')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: '.', code: 'Slash', ctrlKey: true})), 'ctrl-/')
        currentKeymap = require('./helpers/keymaps/mac-hebrew')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: ']', code: 'BracketLeft', ctrlKey: true})), 'ctrl-[')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: '[', code: 'BracketRight', ctrlKey: true})), 'ctrl-]')

        # Don't use U.S. counterpart for keyboards with all Latin characters
        currentKeymap = require('./helpers/keymaps/mac-turkish')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'ö', code: 'KeyX', metaKey: true})), 'cmd-ö')

        # Don't blow up if A, S, D, or F don't have entries in the keymap
        currentKeymap = {KeyA: null, KeyS: null, KeyD: null, KeyF: null}
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'a', code: 'KeyA', ctrlKey: true})), 'ctrl-a')

      it "translates dead keys to their printable equivalents on macOS, but not Windows", ->
        mockProcessPlatform('darwin')
        currentKeymap = require('./helpers/keymaps/mac-swedish')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'Dead', code: 'BracketRight'})), '¨')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'Dead', code: 'BracketRight', shiftKey: true})), '^')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'Dead', code: 'BracketRight', altKey: true})), '~')

        # We can't determine the character for a dead key on Windows without breaking dead key handling
        # in some cases because they have a terrible API, so we don't try.
        mockProcessPlatform('win32')
        currentKeymap = require('./helpers/keymaps/windows-swedish')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'Dead', code: 'BracketRight'})), 'dead')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'Dead', code: 'BracketRight', shiftKey: true})), 'shift-dead')
        assert.equal(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent({key: 'Dead', code: 'BracketRight', ctrlKey: true, altKey: true, shiftKey: true})), 'ctrl-alt-shift-dead')

    describe "when custom keystroke resolvers are installed", ->
      it "resolves to the keystroke string of the most recently-installed resolver returning a defined value", ->
        mockProcessPlatform('darwin')
        currentKeymap = require('./helpers/keymaps/mac-swiss-german')
        currentLayoutName = 'com.apple.keylayout.SwissGerman'
        stub(KeyboardLayout, 'getCurrentKeymap', -> currentKeymap)
        stub(KeyboardLayout, 'getCurrentKeyboardLayout', -> currentLayoutName)

        keydownEvent = buildKeydownEvent({key: '@', code: 'KeyG', ctrlKey: true, altKey: true})
        disposable1 = keymapManager.addKeystrokeResolver(({keystroke, event, layoutName, keymap}) ->
          assert.equal(keystroke, 'ctrl-alt-g')
          assert.equal(event, keydownEvent)
          assert.equal(layoutName, currentLayoutName)
          assert.equal(keymap, currentKeymap)

          # simulate the user wishing to honor the alt-modified character in the presence of other modifiers
          'ctrl-@'
        )
        assert.equal(keymapManager.keystrokeForKeyboardEvent(keydownEvent), 'ctrl-@')

        # Test that multiple keytsroke resolvers cascade
        disposable2 = keymapManager.addKeystrokeResolver(({keystroke}) ->
          assert.equal(keystroke, 'ctrl-@')
          # Ensure that we normalize the returned custom keystroke resolved
          'alt-ctrl-X'
        )
        expectedKeystroke = 'ctrl-alt-shift-X'
        disposable3 = keymapManager.addKeystrokeResolver(({keystroke}) ->
          assert.equal(keystroke, expectedKeystroke)
          null
        )
        assert.equal(keymapManager.keystrokeForKeyboardEvent(keydownEvent), expectedKeystroke)

        # Test that keystroke resolvers can be disposed
        disposable2.dispose()
        expectedKeystroke = 'ctrl-@'
        assert.equal(keymapManager.keystrokeForKeyboardEvent(keydownEvent), expectedKeystroke)

  describe "::findKeyBindings({command, target, keystrokes})", ->
    [elementA, elementB] = []
    beforeEach ->
      elementA = appendContent $$ ->
        @div class: 'a', ->
          @div class: 'b c'
          @div class: 'd'
      elementB = elementA.querySelector('.b.c')

      keymapManager.add 'test',
        '.a':
          'ctrl-a': 'x'
          'ctrl-b': 'y'
        '.b':
          'ctrl-c': 'x'
        '.b.c':
          'ctrl-d': 'x'
        '.d':
          'ctrl-e': 'x'

    describe "when only passed a command", ->
      it "returns all bindings that dispatch the given command", ->
        keystrokes = keymapManager.findKeyBindings(command: 'x').map((b) -> b.keystrokes).sort()
        assert.deepEqual(keystrokes, ['ctrl-a', 'ctrl-c', 'ctrl-d', 'ctrl-e'])

    describe "when only passed a target", ->
      it "returns all bindings that can be invoked from the given target", ->
        keystrokes = keymapManager.findKeyBindings(target: elementB).map((b) -> b.keystrokes)
        assert.deepEqual(keystrokes, ['ctrl-d', 'ctrl-c', 'ctrl-b', 'ctrl-a'])

    describe "when passed keystrokes", ->
      it "returns all bindings that can be invoked with the given keystrokes", ->
        keystrokes = keymapManager.findKeyBindings(keystrokes: 'ctrl-a').map((b) -> b.keystrokes)
        assert.deepEqual(keystrokes, ['ctrl-a'])

    describe "when passed a command and a target", ->
      it "returns all bindings that would invoke the given command from the given target element, ordered by specificity", ->
        keystrokes = keymapManager.findKeyBindings(command: 'x', target: elementB).map((b) -> b.keystrokes)
        assert.deepEqual(keystrokes, ['ctrl-d', 'ctrl-c', 'ctrl-a'])

  describe "::loadKeymap(path, options)", ->
    @timeout(5000)

    beforeEach ->
      getFakeClock().uninstall()

    describe "if called with a file path", ->
      it "loads the keybindings from the file at the given path", ->
        keymapManager.loadKeymap(path.join(__dirname, 'fixtures', 'a.cson'))
        assert.equal(keymapManager.findKeyBindings(command: 'x').length, 1)

      describe "if called with watch: true", ->
        [keymapFilePath, subscription] = []

        beforeEach ->
          keymapFilePath = path.join(temp.mkdirSync('keymap-manager-spec'), "keymapManager.cson")
          fs.writeFileSync keymapFilePath, """
            '.a': 'ctrl-a': 'x'
          """
          keymapManager.loadKeymap(keymapFilePath, watch: true)
          subscription = keymapManager.watchSubscriptions[keymapFilePath]
          assert.equal(keymapManager.findKeyBindings(command: 'x').length, 1)

        describe "when the file is changed", ->
          it "reloads the file's key bindings and notifies ::onDidReloadKeymap observers with the keymap path", (done) ->
            done = debounce(done, 500)

            fs.writeFileSync keymapFilePath, """
              '.a': 'ctrl-a': 'y'
              '.b': 'ctrl-b': 'z'
            """

            keymapManager.onDidReloadKeymap (event) ->
              assert.equal(event.path, keymapFilePath)
              assert.equal(keymapManager.findKeyBindings(command: 'x').length, 0)
              assert.equal(keymapManager.findKeyBindings(command: 'y').length, 1)
              assert.equal(keymapManager.findKeyBindings(command: 'z').length, 1)
              done()

          it "reloads the file's key bindings and notifies ::onDidReloadKeymap observers with the keymap path even if the file is empty", (done) ->
            done = debounce(done, 500)

            fs.writeFileSync keymapFilePath, ""

            keymapManager.onDidReloadKeymap (event) ->
              assert.equal(event.path, keymapFilePath)
              assert.equal(keymapManager.getKeyBindings().length, 0)
              done()

          it "reloads the file's key bindings and notifies ::onDidReloadKeymap observers with the keymap path even if the file has only comments", (done) ->
            done = debounce(done, 500)

            fs.writeFileSync keymapFilePath, """
            #  '.a': 'ctrl-a': 'y'
            #  '.b': 'ctrl-b': 'z'
            """

            keymapManager.onDidReloadKeymap (event) ->
              assert.equal(event.path, keymapFilePath)
              assert.equal(keymapManager.getKeyBindings().length, 0)
              done()

          it "emits an event, logs a warning and does not reload if there is a problem reloading the file", (done) ->
            done = debounce(done, 500)

            stub(console, 'warn')
            fs.writeFileSync keymapFilePath, "junk1."

            keymapManager.onDidFailToReadFile ->
              assert(console.warn.callCount > 0)
              assert.equal(keymapManager.findKeyBindings(command: 'x').length, 1)
              done()

        describe "when the file is removed", ->
          it "removes the bindings and notifies ::onDidUnloadKeymap observers with keymap path", (done) ->
            fs.removeSync(keymapFilePath)

            keymapManager.onDidUnloadKeymap (event) ->
              assert.equal(event.path, keymapFilePath)
              assert.equal(keymapManager.findKeyBindings(command: 'x').length, 0)
              done()

        describe "when the file is moved", ->
          it "removes the bindings", (done) ->
            newFilePath = path.join(temp.mkdirSync('keymap-manager-spec'), "other-guy.cson")
            fs.moveSync(keymapFilePath, newFilePath)

            keymapManager.onDidUnloadKeymap (event) ->
              assert.equal(event.path, keymapFilePath)
              assert.equal(keymapManager.findKeyBindings(command: 'x').length, 0)
              done()

        it "allows the watch to be cancelled via the returned subscription", (done) ->
          done = debounce(done, 100)

          subscription.dispose()
          fs.writeFileSync keymapFilePath, """
            '.a': 'ctrl-a': 'y'
            '.b': 'ctrl-b': 'z'
          """

          reloaded = false
          keymapManager.onDidReloadKeymap -> reloaded = true

          afterWaiting = ->
            assert(not reloaded)

            # Can start watching again after cancelling
            keymapManager.loadKeymap(keymapFilePath, watch: true)
            fs.writeFileSync keymapFilePath, """
              '.a': 'ctrl-a': 'q'
            """

            keymapManager.onDidReloadKeymap ->
              assert.equal(keymapManager.findKeyBindings(command: 'q').length, 1)
              done()

          setTimeout(afterWaiting, 500)

    describe "if called with a directory path", ->
      it "loads all platform compatible keybindings files in the directory", ->
        stub(keymapManager, 'getOtherPlatforms').returns(['os2'])

        keymapManager.loadKeymap(path.join(__dirname, 'fixtures'))
        assert.equal(keymapManager.findKeyBindings(command: 'x').length, 1)
        assert.equal(keymapManager.findKeyBindings(command: 'y').length, 1)
        assert.equal(keymapManager.findKeyBindings(command: 'z').length, 1)
        assert.equal(keymapManager.findKeyBindings(command: 'X').length, 0)
        assert.equal(keymapManager.findKeyBindings(command: 'Y').length, 0)

  describe "events", ->
    it "emits `matched` when a key binding matches an event", ->
      handler = stub()
      keymapManager.onDidMatchBinding handler
      keymapManager.add "test",
        "body":
          "ctrl-x": "used-command"
        "*":
          "ctrl-x": "unused-command"
        ".not-in-the-dom":
          "ctrl-x": "unmached-command"

      keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'x', ctrlKey: true, target: document.body))
      assert.equal(handler.callCount, 1)

      {keystrokes, binding, keyboardEventTarget} = handler.firstCall.args[0]
      assert.equal(keystrokes, 'ctrl-x')
      assert.equal(binding.command, 'used-command')
      assert.equal(keyboardEventTarget, document.body)

    it "emits `matched-partially` when a key binding partially matches an event", ->
      handler = stub()
      keymapManager.onDidPartiallyMatchBindings handler
      keymapManager.add "test",
        "body":
          "ctrl-x 1": "command-1"
          "ctrl-x 2": "command-2"
          "a c ^c ^a": "command-3"

      keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'x', ctrlKey: true, target: document.body))
      assert.equal(handler.callCount, 1)

      {keystrokes, partiallyMatchedBindings, keyboardEventTarget} = handler.firstCall.args[0]
      assert.equal(keystrokes, 'ctrl-x')
      assert.equal(partiallyMatchedBindings.length, 2)
      assert.deepEqual(partiallyMatchedBindings.map(({command}) -> command), ['command-1', 'command-2'])
      assert.equal(keyboardEventTarget, document.body)

    it "emits `matched-partially` when a key binding that contains keyup keystrokes partially matches an event", ->
      handler = stub()
      keymapManager.onDidPartiallyMatchBindings handler
      keymapManager.add "test",
        "body":
          "a c ^c ^a": "command-1"

      keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'a', target: document.body))
      keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'c', target: document.body))
      assert(handler.callCount > 0)

      {keystrokes, partiallyMatchedBindings, keyboardEventTarget} = handler.firstCall.args[0]
      assert.equal(keystrokes, 'a')

      {keystrokes, partiallyMatchedBindings, keyboardEventTarget} = handler.getCall(1).args[0]
      assert.equal(keystrokes, 'a c')
      assert.equal(partiallyMatchedBindings.length, 1)
      assert.deepEqual(partiallyMatchedBindings.map(({command}) -> command), ['command-1'])
      assert.equal(keyboardEventTarget, document.body)

      handler.reset()
      keymapManager.handleKeyboardEvent(buildKeyupEvent(key: 'c', target: document.body))
      assert.equal(handler.callCount, 1)

      {keystrokes, partiallyMatchedBindings, keyboardEventTarget} = handler.firstCall.args[0]
      assert.equal(keystrokes, 'a c ^c')
      assert.equal(partiallyMatchedBindings.length, 1)
      assert.deepEqual(partiallyMatchedBindings.map(({command}) -> command), ['command-1'])
      assert.equal(keyboardEventTarget, document.body)

    it "emits `match-failed` when no key bindings match the event", ->
      handler = stub()
      keymapManager.onDidFailToMatchBinding handler
      keymapManager.add "test",
        "body":
          "ctrl-x": "command"

      keymapManager.handleKeyboardEvent(buildKeydownEvent(key: 'y', ctrlKey: true, target: document.body))
      assert.equal(handler.callCount, 1)

      {keystrokes, keyboardEventTarget} = handler.firstCall.args[0]
      assert.equal(keystrokes, 'ctrl-y')
      assert.equal(keyboardEventTarget, document.body)
