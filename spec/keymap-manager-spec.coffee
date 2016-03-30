path = require 'path'
fs = require 'fs-plus'
temp = require 'temp'
{$$} = require 'space-pencil'
{appendContent} = require './spec-helper'
KeymapManager = require '../src/keymap-manager'
{buildKeydownEvent, buildKeyupEvent} = KeymapManager

describe "KeymapManager", ->
  keymapManager = null

  beforeEach ->
    keymapManager = new KeymapManager

  afterEach ->
    keymapManager.destroy()

  describe "::handleKeyboardEvent(event)", ->
    describe "when the keystroke matches no bindings", ->
      it "does not prevent the event's default action", ->
        event = buildKeydownEvent('q')
        keymapManager.handleKeyboardEvent(event)
        expect(event.defaultPrevented).toBe false

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
        keymapManager.handleKeyboardEvent(buildKeydownEvent('y', ctrl: true, target: elementB))
        expect(events.length).toBe 1
        expect(events[0].type).toBe 'y-command'
        expect(events[0].target).toBe elementB

        events = []
        keymapManager.handleKeyboardEvent(buildKeydownEvent('x', ctrl: true, target: elementB))
        expect(events.length).toBe 1
        expect(events[0].type).toBe 'x-command'
        expect(events[0].target).toBe elementB

      it "prevents the default action", ->
        event = buildKeydownEvent('y', ctrl: true, target: elementB)
        keymapManager.handleKeyboardEvent(event)
        expect(event.defaultPrevented).toBe true

      describe "if .abortKeyBinding() is called on the command event", ->
        it "proceeds directly to the next matching binding and does not prevent the keyboard event's default action", ->
          elementB.addEventListener 'y-command', (e) -> events.push(e); e.abortKeyBinding()
          elementB.addEventListener 'y-command', (e) -> events.push(e) # should never be called
          elementB.addEventListener 'z-command', (e) -> events.push(e); e.abortKeyBinding()

          event = buildKeydownEvent('y', ctrl: true, target: elementB)
          keymapManager.handleKeyboardEvent(event)
          expect(event.defaultPrevented).toBe false

          expect(events.length).toBe 3
          expect(events[0].type).toBe 'y-command'
          expect(events[0].target).toBe elementB
          expect(events[1].type).toBe 'z-command'
          expect(events[1].target).toBe elementB
          expect(events[2].type).toBe 'y-command'
          expect(events[2].target).toBe elementB

      describe "if the keyboard event's target is document.body", ->
        it "starts matching keybindings at the .defaultTarget", ->
          keymapManager.defaultTarget = elementA
          keymapManager.handleKeyboardEvent(buildKeydownEvent('y', ctrl: true, target: document.body))
          expect(events.length).toBe 1
          expect(events[0].type).toBe 'y-command'
          expect(events[0].target).toBe elementA

      describe "if the matching binding's command is 'native!'", ->
        it "terminates without preventing the browser's default action", ->
          elementA.addEventListener 'native!', (e) -> events.push(e)
          keymapManager.add "test",
            ".b":
              "ctrl-y": "native!"

          event = buildKeydownEvent('y', ctrl: true, target: elementB)
          keymapManager.handleKeyboardEvent(event)
          expect(events).toEqual []
          expect(event.defaultPrevented).toBe false

      describe "if the matching binding's command is 'unset!'", ->
        it "continues searching for a matching binding on the parent element", ->
          elementA.addEventListener 'unset!', (e) -> events.push(e)
          keymapManager.add "test",
            ".a":
              "ctrl-y": "x-command"
            ".b":
              "ctrl-y": "unset!"

          event = buildKeydownEvent('y', ctrl: true, target: elementB)
          keymapManager.handleKeyboardEvent(event)
          expect(events.length).toBe 1
          expect(events[0].type).toBe 'x-command'
          expect(event.defaultPrevented).toBe true

      describe "if the matching binding's command is 'unset!' and there is another match", ->
        it "immediately matches the other match", ->
          elementA.addEventListener 'unset!', (e) -> events.push(e)
          keymapManager.add "test",
            ".a":
              "ctrl-y": "x-command"
              "ctrl-y ctrl-y": "unset!"
          event = buildKeydownEvent('y', ctrl: true, target: elementA)
          keymapManager.handleKeyboardEvent(event)
          expect(events.length).toBe 1
          expect(events[0].type).toBe 'x-command'

      describe "if the matching binding's command is 'abort!'", ->
        it "stops searching for a matching binding immediately and emits no command event", ->
          elementA.addEventListener 'abort!', (e) -> events.push(e)
          keymapManager.add "test",
            ".a":
              "ctrl-y": "y-command"
              "ctrl-x": "x-command"
            ".b":
              "ctrl-y": "abort!"

          event = buildKeydownEvent('y', ctrl: true, target: elementB)
          keymapManager.handleKeyboardEvent(event)
          expect(events.length).toBe 0
          expect(event.defaultPrevented).toBe true

          keymapManager.handleKeyboardEvent(buildKeydownEvent('x', ctrl: true, target: elementB))
          expect(events.length).toBe 1

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

      describe "when the bindings have selectors with different specificity", ->
        beforeEach ->
          keymapManager.add "test",
            ".b.c":
              "ctrl-x": "command-1"
            ".b":
              "ctrl-x": "command-2"

        it "dispatches the command associated with the most specific binding", ->
          keymapManager.handleKeyboardEvent(buildKeydownEvent('x', ctrl: true, target: elementB))
          expect(events.length).toBe 1
          expect(events[0].type).toBe 'command-1'
          expect(events[0].target).toBe elementB

      describe "when the bindings have selectors with the same specificity", ->
        it "dispatches the command associated with the most recently added binding", ->
          keymapManager.add "test",
            ".b.c":
              "ctrl-x": "command-1"
            ".c.d":
              "ctrl-x": "command-2"

          keymapManager.handleKeyboardEvent(buildKeydownEvent('x', ctrl: true, target: elementB))

          expect(events.length).toBe 1
          expect(events[0].type).toBe 'command-2'
          expect(events[0].target).toBe elementB

        it "dispatches the command associated with the binding which has the highest priority", ->
          keymapManager.add "keybindings-with-super-priority", {".c.d": {"ctrl-x": "command-1"}}, 2
          keymapManager.add "normal-keybindings", {".b.d": {"ctrl-x": "command-3"}}, 0
          keymapManager.add "keybindings-with-priority", {".b.c": {"ctrl-x": "command-2"}}, 1

          keymapManager.handleKeyboardEvent(buildKeydownEvent('x', ctrl: true, target: elementB))

          expect(events.length).toBe 1
          expect(events[0].type).toBe 'command-1'
          expect(events[0].target).toBe elementB

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
            'v i v a': 'viva!'
            'v i v': 'viv'
          '.editor':
            'v': 'enter-visual-mode'
            'space r r': 'command1'
            'space b': 'something-else'
          '.editor.visual-mode': 'i w': 'select-inside-word'

        events = []
        editor.addEventListener 'textInput', (event) -> events.push("input:#{event.data}")
        workspace.addEventListener 'dog', -> events.push('dog')
        workspace.addEventListener 'viva!', -> events.push('viva!')
        workspace.addEventListener 'viv', -> events.push('viv')
        workspace.addEventListener 'select-inside-word', -> events.push('select-inside-word')
        workspace.addEventListener 'enter-visual-mode', -> events.push('enter-visual-mode'); editor.classList.add('visual-mode')

      describe "when keystrokes match a series of commands", ->
        it "matches the correct actions", ->
          keymapManager.handleKeyboardEvent(buildKeydownEvent('space', target: editor))
          keymapManager.handleKeyboardEvent(buildKeyupEvent('space', target: editor))
          keymapManager.handleKeyboardEvent(buildKeydownEvent('r', target: editor))
          keymapManager.handleKeyboardEvent(buildKeyupEvent('r', target: editor))
          keymapManager.handleKeyboardEvent(buildKeydownEvent('a', target: editor))
          # expect this to not raise a gnarly stack level too deep exception

      describe "when subsequent keystrokes yield an exact match", ->
        it "dispatches the command associated with the matched multi-keystroke binding", ->
          keymapManager.handleKeyboardEvent(buildKeydownEvent('v', target: editor))
          keymapManager.handleKeyboardEvent(buildKeyupEvent('v', target: editor))
          keymapManager.handleKeyboardEvent(buildKeydownEvent('i', target: editor))
          keymapManager.handleKeyboardEvent(buildKeyupEvent('i', target: editor))
          keymapManager.handleKeyboardEvent(buildKeydownEvent('v', target: editor))
          keymapManager.handleKeyboardEvent(buildKeyupEvent('v', target: editor))
          keymapManager.handleKeyboardEvent(buildKeydownEvent('a', target: editor))
          keymapManager.handleKeyboardEvent(buildKeyupEvent('a', target: editor))
          expect(events).toEqual ['viva!']

      describe "when subsequent keystrokes yield no matches", ->
        it "disables the bindings with the longest keystroke sequences and replays the queued keystrokes", ->
          keymapManager.handleKeyboardEvent(vEvent = buildKeydownEvent('v', target: editor))
          keymapManager.handleKeyboardEvent(iEvent = buildKeydownEvent('i', target: editor))
          keymapManager.handleKeyboardEvent(wEvent = buildKeydownEvent('w', target: editor))
          expect(vEvent.defaultPrevented).toBe true
          expect(iEvent.defaultPrevented).toBe true
          expect(wEvent.defaultPrevented).toBe true
          expect(events).toEqual ['enter-visual-mode', 'select-inside-word']

          events = []
          keymapManager.handleKeyboardEvent(vEvent = buildKeydownEvent('v', target: editor))
          keymapManager.handleKeyboardEvent(iEvent = buildKeydownEvent('i', target: editor))
          keymapManager.handleKeyboardEvent(kEvent = buildKeydownEvent('k', target: editor))
          expect(vEvent.defaultPrevented).toBe true
          expect(iEvent.defaultPrevented).toBe true
          expect(kEvent.defaultPrevented).toBe false
          expect(events).toEqual ['enter-visual-mode', 'input:i']
          expect(clearTimeout).toHaveBeenCalled()

        it "dispatches a text-input event for any replayed keyboard events that would have inserted characters", ->
          keymapManager.handleKeyboardEvent(buildKeydownEvent('d', target: editor))
          keymapManager.handleKeyboardEvent(buildKeydownEvent('o', target: editor))
          keymapManager.handleKeyboardEvent(lastEvent = buildKeydownEvent('q', target: editor))

          expect(events).toEqual ['input:d', 'input:o']
          expect(lastEvent.defaultPrevented).toBe false # inserted as normal

      describe "when the currently queued keystrokes exactly match at least one binding", ->
        it "disables partially-matching bindings and replays the queued keystrokes if the ::partialMatchTimeout expires", ->
          keymapManager.handleKeyboardEvent(buildKeydownEvent('v', target: editor))
          expect(events).toEqual []
          advanceClock(keymapManager.getPartialMatchTimeout())
          expect(events).toEqual ['enter-visual-mode']

          events = []
          keymapManager.handleKeyboardEvent(buildKeydownEvent('v', target: editor))
          keymapManager.handleKeyboardEvent(buildKeyupEvent('v', target: editor))
          keymapManager.handleKeyboardEvent(buildKeydownEvent('i', target: editor))
          keymapManager.handleKeyboardEvent(buildKeyupEvent('i', target: editor))
          expect(events).toEqual []
          advanceClock(keymapManager.getPartialMatchTimeout())
          expect(events).toEqual ['enter-visual-mode', 'input:i']

          events = []
          keymapManager.handleKeyboardEvent(buildKeydownEvent('v', target: editor))
          keymapManager.handleKeyboardEvent(buildKeyupEvent('v', target: editor))
          keymapManager.handleKeyboardEvent(buildKeydownEvent('i', target: editor))
          keymapManager.handleKeyboardEvent(buildKeyupEvent('i', target: editor))
          keymapManager.handleKeyboardEvent(buildKeydownEvent('v', target: editor))
          expect(events).toEqual []
          advanceClock(keymapManager.getPartialMatchTimeout())
          expect(events).toEqual ['viv']

        it "does not enter a pending state or prevent the default action if the matching binding's command is 'native!'", ->
          keymapManager.add 'test', '.workspace': 'v': 'native!'
          event = buildKeydownEvent('v', target: editor)
          keymapManager.handleKeyboardEvent(event)
          expect(event.defaultPrevented).toBe false
          expect(global.setTimeout).not.toHaveBeenCalled()
          expect(keymapManager.queuedKeyboardEvents.length).toBe 0

      describe "when the first queued keystroke corresponds to a character insertion", ->
        it "disables partially-matching bindings and replays the queued keystrokes if the ::partialMatchTimeout expires", ->
          keymapManager.handleKeyboardEvent(buildKeydownEvent('d', target: editor))
          keymapManager.handleKeyboardEvent(buildKeydownEvent('o', target: editor))
          advanceClock(keymapManager.getPartialMatchTimeout())

          expect(events).toEqual ['input:d', 'input:o']

      describe "when the currently queued keystrokes don't exactly match any bindings", ->
        it "never times out of the pending state", ->
          keymapManager.add 'test',
            '.workspace':
              'ctrl-d o g': 'control-dog'

          workspace.addEventListener 'control-dog', -> events.push('control-dog')

          keymapManager.handleKeyboardEvent(buildKeydownEvent('ctrl-d', target: editor))
          keymapManager.handleKeyboardEvent(buildKeydownEvent('o', target: editor))

          advanceClock(keymapManager.getPartialMatchTimeout())
          advanceClock(keymapManager.getPartialMatchTimeout())

          expect(events).toEqual []
          keymapManager.handleKeyboardEvent(buildKeydownEvent('g', target: editor))
          expect(events).toEqual ['control-dog']

      describe "when the partially matching bindings all map to the 'unset!' directive", ->
        it "ignores the 'unset!' bindings and invokes the command associated with the matching binding as normal", ->
          keymapManager.add 'test-2',
            '.workspace':
              'v i v a': 'unset!'
              'v i v': 'unset!'

          keymapManager.handleKeyboardEvent(buildKeydownEvent('v', target: editor))

          expect(events).toEqual ['enter-visual-mode']

      describe "when a subsequent keystroke begins a new match of an already pending binding", ->
        it "recognizes the match", ->
          keymapManager.handleKeyboardEvent(buildKeydownEvent('d', target: editor))
          keymapManager.handleKeyboardEvent(buildKeydownEvent('o', target: editor))
          keymapManager.handleKeyboardEvent(buildKeydownEvent('d', target: editor))
          keymapManager.handleKeyboardEvent(buildKeydownEvent('o', target: editor))
          keymapManager.handleKeyboardEvent(buildKeydownEvent('g', target: editor))

          expect(events).toEqual ['input:d', 'input:o', 'dog']

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

        keymapManager.add "test",
          ".a":
            "ctrl-y": "y-command"
            "ctrl-y ^ctrl": "y-command-ctrl-up"
            "ctrl-x ^ctrl": "x-command-ctrl-up"
            "ctrl-y ^y ^ctrl": "y-command-y-up-ctrl-up"
            "a b c ^b ^a ^c": "abc-secret-code-command"

      it "dispatches the command for a binding containing only keydown events immediately even when there is a corresponding multi-stroke binding that contains only other keyup events", ->
        keymapManager.handleKeyboardEvent(buildKeydownEvent('y', ctrl: true, target: elementA))
        expect(events).toEqual ['y-keydown']

      it "dispatches the command when a matching keystroke precedes it", ->
        keymapManager.handleKeyboardEvent(buildKeydownEvent('y', ctrl: true, target: elementA))
        expect(events).toEqual ['y-keydown']
        keymapManager.handleKeyboardEvent(buildKeyupEvent('y', ctrl: true, cmd: true, shift: true, alt: true, target: elementA))
        expect(events).toEqual ['y-keydown']
        keymapManager.handleKeyboardEvent(buildKeyupEvent('ctrl', target: elementA))
        advanceClock(keymapManager.getPartialMatchTimeout())
        expect(events).toEqual ['y-keydown', 'y-up-ctrl-keyup']

      it "dispatches the command multiple times when multiple keydown events for the binding come in before the binding with a keyup handler", ->
        keymapManager.handleKeyboardEvent(buildKeydownEvent('y', ctrl: true, target: elementA))
        expect(events).toEqual ['y-keydown']
        keymapManager.handleKeyboardEvent(buildKeyupEvent('y', ctrl: true, target: elementA))
        expect(events).toEqual ['y-keydown']
        keymapManager.handleKeyboardEvent(buildKeydownEvent('y', ctrl: true, target: elementA))
        expect(events).toEqual ['y-keydown', 'y-keydown']
        advanceClock(keymapManager.getPartialMatchTimeout())
        expect(events).toEqual ['y-keydown', 'y-keydown']

      it "dispatches the command when the modifier is lifted before the character", ->
        keymapManager.handleKeyboardEvent(buildKeydownEvent('y', ctrl: true, target: elementA))
        expect(events).toEqual ['y-keydown']
        keymapManager.handleKeyboardEvent(buildKeyupEvent('ctrl', target: elementA))
        expect(events).toEqual ['y-keydown', 'y-ctrl-keyup']
        advanceClock(keymapManager.getPartialMatchTimeout())
        expect(events).toEqual ['y-keydown', 'y-ctrl-keyup']

      it "dispatches the command when extra user-generated keyup events are not specified in the binding", ->
        keymapManager.handleKeyboardEvent(buildKeydownEvent('x', ctrl: true, target: elementA))
        keymapManager.handleKeyboardEvent(buildKeyupEvent('x', ctrl: true, target: elementA)) # not specified in binding
        keymapManager.handleKeyboardEvent(buildKeyupEvent('ctrl', target: elementA))
        advanceClock(keymapManager.getPartialMatchTimeout())
        expect(events).toEqual ['x-ctrl-keyup']

      it "does _not_ dispatch the command when extra user-generated keydown events are not specified in the binding", ->
        keymapManager.handleKeyboardEvent(buildKeydownEvent('y', ctrl: true, target: elementA))
        expect(events).toEqual ['y-keydown']
        keymapManager.handleKeyboardEvent(buildKeydownEvent('z', ctrl: true, target: elementA)) # not specified in binding
        expect(events).toEqual ['y-keydown']
        keymapManager.handleKeyboardEvent(buildKeyupEvent('ctrl', target: elementA))
        advanceClock(keymapManager.getPartialMatchTimeout())
        expect(events).toEqual ['y-keydown']

      it "dispatches the command when multiple keyup keystrokes are specified", ->
        keymapManager.handleKeyboardEvent(buildKeydownEvent('a', target: elementA))
        keymapManager.handleKeyboardEvent(buildKeydownEvent('b', target: elementA))
        keymapManager.handleKeyboardEvent(buildKeydownEvent('c', target: elementA))
        keymapManager.handleKeyboardEvent(buildKeyupEvent('a', target: elementA))
        keymapManager.handleKeyboardEvent(buildKeyupEvent('b', target: elementA))
        keymapManager.handleKeyboardEvent(buildKeyupEvent('c', target: elementA))
        advanceClock(keymapManager.getPartialMatchTimeout())
        expect(events).toEqual []

        keymapManager.handleKeyboardEvent(buildKeydownEvent('a', target: elementA))
        keymapManager.handleKeyboardEvent(buildKeydownEvent('b', target: elementA))
        keymapManager.handleKeyboardEvent(buildKeydownEvent('c', target: elementA))
        keymapManager.handleKeyboardEvent(buildKeyupEvent('b', target: elementA))
        keymapManager.handleKeyboardEvent(buildKeyupEvent('a', target: elementA))
        keymapManager.handleKeyboardEvent(buildKeyupEvent('c', target: elementA))
        advanceClock(keymapManager.getPartialMatchTimeout())
        expect(events).toEqual ['abc-secret-code']

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
      keymapManager.handleKeyboardEvent(buildKeydownEvent('a', ctrl: true, target: element))
      expect(events).toEqual ['command-b']

    it "does not enqueue keydown events consisting only of modifier keys", ->
      element = $$ -> @div class: 'a'
      keymapManager.add 'test', '.a': 'ctrl-a ctrl-alt-b': 'command'
      events = []
      element.addEventListener 'command', -> events.push('command')

      # Simulate keydown events for the modifier key being pressed on its own
      # prior to the key it is modifying.
      keymapManager.handleKeyboardEvent(buildKeydownEvent('ctrl', ctrl: true, target: element))
      keymapManager.handleKeyboardEvent(buildKeydownEvent('a', ctrl: true, target: element))
      keymapManager.handleKeyboardEvent(buildKeydownEvent('ctrl', ctrl: true, target: element))
      keymapManager.handleKeyboardEvent(buildKeydownEvent('alt', ctrl: true, target: element))
      keymapManager.handleKeyboardEvent(buildKeydownEvent('b', ctrl: true, alt: true, target: element))

      expect(events).toEqual ['command']

    it "allows solo modifier-keys to be bound", ->
      element = $$ -> @div class: 'a'
      keymapManager.add 'test', '.a': 'ctrl': 'command'
      events = []
      element.addEventListener 'command', -> events.push('command')

      keymapManager.handleKeyboardEvent(buildKeydownEvent('ctrl', target: element))
      expect(events).toEqual ['command']

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
        expect(e.target).toBe elementC
        expect(e.currentTarget).toBe elementB
      elementC.addEventListener 'command', (e) ->
        events.push('c')
        expect(e.target).toBe elementC
        expect(e.currentTarget).toBe elementC

      keymapManager.handleKeyboardEvent(buildKeydownEvent('x', target: elementC))

      expect(events).toEqual ['c', 'b1']

  describe "::add(source, bindings)", ->
    it "normalizes keystrokes containing capitalized alphabetic characters", ->
      keymapManager.add 'test', '*': 'ctrl-shift-l': 'a'
      keymapManager.add 'test', '*': 'ctrl-shift-L': 'b'
      keymapManager.add 'test', '*': 'ctrl-L': 'c'
      expect(keymapManager.findKeyBindings(command: 'a')[0].keystrokes).toBe 'ctrl-shift-L'
      expect(keymapManager.findKeyBindings(command: 'b')[0].keystrokes).toBe 'ctrl-shift-L'
      expect(keymapManager.findKeyBindings(command: 'c')[0].keystrokes).toBe 'ctrl-shift-L'

    it "normalizes the order of modifier keys based on the Apple interface guidelines", ->
      keymapManager.add 'test', '*': 'alt-cmd-ctrl-shift-l': 'a'
      keymapManager.add 'test', '*': 'shift-ctrl-l': 'b'
      keymapManager.add 'test', '*': 'alt-ctrl-l': 'c'
      keymapManager.add 'test', '*': 'ctrl-alt--': 'd'

      expect(keymapManager.findKeyBindings(command: 'a')[0].keystrokes).toBe 'ctrl-alt-shift-cmd-L'
      expect(keymapManager.findKeyBindings(command: 'b')[0].keystrokes).toBe 'ctrl-shift-L'
      expect(keymapManager.findKeyBindings(command: 'c')[0].keystrokes).toBe 'ctrl-alt-l'
      expect(keymapManager.findKeyBindings(command: 'd')[0].keystrokes).toBe 'ctrl-alt--'

    it "rejects bindings with unknown modifier keys and logs a warning to the console", ->
      spyOn(console, 'warn')
      keymapManager.add 'test', '*': 'meta-shift-A': 'a'
      expect(console.warn).toHaveBeenCalled()

      event = buildKeydownEvent('A', shift: true, target: document.body)
      keymapManager.handleKeyboardEvent(event)
      expect(event.defaultPrevented).toBe false

    it "rejects bindings with an invalid selector and logs a warning to the console", ->
      spyOn(console, 'warn')
      expect(keymapManager.add('test', '<>': 'shift-a': 'a')).toBeUndefined()
      expect(console.warn).toHaveBeenCalled()

      event = buildKeydownEvent('A', shift: true, target: document.body)
      keymapManager.handleKeyboardEvent(event)
      expect(event.defaultPrevented).toBe false

    it "rejects bindings with an empty command and logs a warning to the console", ->
      spyOn(console, 'warn')
      expect(keymapManager.add('test', 'body': 'shift-a': '')).toBeUndefined()
      expect(console.warn).toHaveBeenCalled()

      event = buildKeydownEvent('A', shift: true, target: document.body)
      keymapManager.handleKeyboardEvent(event)
      expect(event.defaultPrevented).toBe false

    it "rejects bindings without a command and logs a warning to the console", ->
      spyOn(console, 'warn')
      expect(keymapManager.add('test', 'body': 'shift-a': null)).toBeUndefined()
      expect(console.warn).toHaveBeenCalled()

      event = buildKeydownEvent('A', shift: true, target: document.body)
      keymapManager.handleKeyboardEvent(event)
      expect(event.defaultPrevented).toBe false

    it "returns a disposable allowing the added bindings to be removed", ->
      disposable1 = keymapManager.add 'foo',
        '.a':
          'ctrl-a': 'x'
        '.b':
          'ctrl-b': 'y'

      disposable2 = keymapManager.add 'bar',
        '.c':
          'ctrl-c': 'z'

      expect(keymapManager.findKeyBindings(command: 'x').length).toBe 1
      expect(keymapManager.findKeyBindings(command: 'y').length).toBe 1
      expect(keymapManager.findKeyBindings(command: 'z').length).toBe 1

      disposable2.dispose()

      expect(keymapManager.findKeyBindings(command: 'x').length).toBe 1
      expect(keymapManager.findKeyBindings(command: 'y').length).toBe 1
      expect(keymapManager.findKeyBindings(command: 'z').length).toBe 0

  describe "::keystrokeForKeyboardEvent(event)", ->
    describe "when no modifiers are pressed", ->
      it "returns a string that identifies the unmodified keystroke", ->
        expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('a'))).toBe 'a'
        expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('['))).toBe '['
        expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('*'))).toBe '*'
        expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('left'))).toBe 'left'
        expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('\b'))).toBe 'backspace'

    describe "when a modifier key is combined with a non-modifier key", ->
      it "returns a string that identifies the modified keystroke", ->
        expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('a', alt: true))).toBe 'alt-a'
        expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('[', cmd: true))).toBe 'cmd-['
        expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('*', ctrl: true))).toBe 'ctrl-*'
        expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('left', ctrl: true, alt: true, cmd: true))).toBe 'ctrl-alt-cmd-left'
        expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('A', shift: true))).toBe 'shift-A'
        expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('a', ctrl: true, shift: true))).toBe 'ctrl-shift-A'
        expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('{', shift: true))).toBe '{'
        expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('left', shift: true))).toBe 'shift-left'
        expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('Left', shift: true))).toBe 'shift-left'

    describe "when a numpad key is pressed", ->
      it "returns a string that identifies the key as the appropriate num-key", ->
        expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+0041', keyCode: 97, location: 3))).toBe '1'
        expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+0045', keyCode: 101, location: 3))).toBe '5'
        expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+0049', keyCode: 105, location: 3))).toBe '9'
        expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('PageDown', keyCode: 34, location: 3))).toBe 'pagedown'
        expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('PageUp', keyCode: 33, location: 3))).toBe 'pageup'
        expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+004B', keyCode: 107, location: 3))).toBe '+'
        expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+007F', keyCode: 46, location: 3))).toBe 'delete'

    describe "when a non-English keyboard language is used", ->
      it "uses the physical character pressed instead of the character it maps to in the current language", ->
        expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+03B6', cmd: true, keyCode: 122))).toBe 'cmd-z'

    describe "when KeymapManager::dvorakQwertyWorkaroundEnabled is true", ->
      it "uses event.keyCode instead of event.keyIdentifier when event.keyIdentifier is numeric", ->
        keymapManager.dvorakQwertyWorkaroundEnabled = true
        expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+004A', cmd: true, keyCode: 67))).toBe 'cmd-c'

      it "maps the keyCode for delete (46) to the ASCII code for delete (127)", ->
        keymapManager.dvorakQwertyWorkaroundEnabled = true
        expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+007F', keyCode: 46))).toBe 'delete'

    describe "on Windows and Linux", ->
      originalPlatform = null

      beforeEach ->
        originalPlatform = process.platform

      afterEach ->
        Object.defineProperty process, 'platform', value: originalPlatform

      it "corrects a Chromium bug where the keyIdentifier is incorrect for certain keypress events", ->
        testTranslations = ->
          # Number row
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+0030', ctrl: true))).toBe 'ctrl-0'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+0031', ctrl: true))).toBe 'ctrl-1'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+0032', ctrl: true))).toBe 'ctrl-2'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+0033', ctrl: true))).toBe 'ctrl-3'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+0034', ctrl: true))).toBe 'ctrl-4'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+0035', ctrl: true))).toBe 'ctrl-5'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+0036', ctrl: true))).toBe 'ctrl-6'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+0037', ctrl: true))).toBe 'ctrl-7'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+0038', ctrl: true))).toBe 'ctrl-8'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+0039', ctrl: true))).toBe 'ctrl-9'

          # Number row shifted
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+0030', ctrl: true, shift: true))).toBe 'ctrl-)'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+0031', ctrl: true, shift: true))).toBe 'ctrl-!'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+0032', ctrl: true, shift: true))).toBe 'ctrl-@'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+0033', ctrl: true, shift: true))).toBe 'ctrl-#'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+0034', ctrl: true, shift: true))).toBe 'ctrl-$'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+0035', ctrl: true, shift: true))).toBe 'ctrl-%'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+0036', ctrl: true, shift: true))).toBe 'ctrl-^'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+0037', ctrl: true, shift: true))).toBe 'ctrl-&'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+0038', ctrl: true, shift: true))).toBe 'ctrl-*'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+0039', ctrl: true, shift: true))).toBe 'ctrl-('

          # Other symbols
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+00ba', ctrl: true))).toBe 'ctrl-;'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+00bb', ctrl: true))).toBe 'ctrl-='
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+00bc', ctrl: true))).toBe 'ctrl-,'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+00bd', ctrl: true))).toBe 'ctrl--'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+00be', ctrl: true))).toBe 'ctrl-.'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+00bf', ctrl: true))).toBe 'ctrl-/'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+00db', ctrl: true))).toBe 'ctrl-['
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+00dc', ctrl: true))).toBe 'ctrl-\\'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+00dd', ctrl: true))).toBe 'ctrl-]'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+00de', ctrl: true))).toBe 'ctrl-\''

          # Other symbols shifted
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+00ba', ctrl: true, shift: true))).toBe 'ctrl-:'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+00bb', ctrl: true, shift: true))).toBe 'ctrl-+'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+00bc', ctrl: true, shift: true))).toBe 'ctrl-<'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+00bd', ctrl: true, shift: true))).toBe 'ctrl-_'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+00be', ctrl: true, shift: true))).toBe 'ctrl->'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+00bf', ctrl: true, shift: true))).toBe 'ctrl-?'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+00db', ctrl: true, shift: true))).toBe 'ctrl-{'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+00dc', ctrl: true, shift: true))).toBe 'ctrl-|'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+00dd', ctrl: true, shift: true))).toBe 'ctrl-}'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+00de', ctrl: true, shift: true))).toBe 'ctrl-"'

          # Single modifiers
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+00A0', shift: true))).toBe 'shift'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+00A1', shift: true))).toBe 'shift'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+00A2', ctrl: true))).toBe 'ctrl'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+00A3', ctrl: true))).toBe 'ctrl'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+00A4', alt: true))).toBe 'alt'
          expect(keymapManager.keystrokeForKeyboardEvent(buildKeydownEvent('U+00A5', alt: true))).toBe 'alt'

        Object.defineProperty process, 'platform', value: 'win32'
        testTranslations()
        Object.defineProperty process, 'platform', value: 'linux'
        testTranslations()

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
        expect(keystrokes).toEqual ['ctrl-a', 'ctrl-c', 'ctrl-d', 'ctrl-e']

    describe "when only passed a target", ->
      it "returns all bindings that can be invoked from the given target", ->
        keystrokes = keymapManager.findKeyBindings(target: elementB).map((b) -> b.keystrokes)
        expect(keystrokes).toEqual ['ctrl-d', 'ctrl-c', 'ctrl-b', 'ctrl-a']

    describe "when passed keystrokes", ->
      it "returns all bindings that can be invoked with the given keystrokes", ->
        keystrokes = keymapManager.findKeyBindings(keystrokes: 'ctrl-a').map((b) -> b.keystrokes)
        expect(keystrokes).toEqual ['ctrl-a']

    describe "when passed a command and a target", ->
      it "returns all bindings that would invoke the given command from the given target element, ordered by specificity", ->
        keystrokes = keymapManager.findKeyBindings(command: 'x', target: elementB).map((b) -> b.keystrokes)
        expect(keystrokes).toEqual ['ctrl-d', 'ctrl-c', 'ctrl-a']

  describe "::loadKeymap(path, options)", ->
    describe "if called with a file path", ->
      it "loads the keybindings from the file at the given path", ->
        keymapManager.loadKeymap(path.join(__dirname, 'fixtures', 'a.cson'))
        expect(keymapManager.findKeyBindings(command: 'x').length).toBe 1

      describe "if called with watch: true", ->
        [keymapFilePath, subscription] = []

        beforeEach ->
          keymapFilePath = path.join(temp.mkdirSync('keymapManager-spec'), "keymapManager.cson")
          fs.writeFileSync keymapFilePath, """
            '.a': 'ctrl-a': 'x'
          """
          keymapManager.loadKeymap(keymapFilePath, watch: true)
          subscription = keymapManager.watchSubscriptions[keymapFilePath]
          expect(keymapManager.findKeyBindings(command: 'x').length).toBe 1

        describe "when the file is changed", ->
          it "reloads the file's key bindings and notifies ::onDidReloadKeymap observers with the keymap path", ->
            fs.writeFileSync keymapFilePath, """
              '.a': 'ctrl-a': 'y'
              '.b': 'ctrl-b': 'z'
            """

            waitsFor 300, (done) ->
              keymapManager.onDidReloadKeymap (event) ->
                expect(event.path).toBe keymapFilePath
                done()

            runs ->
              expect(keymapManager.findKeyBindings(command: 'x').length).toBe 0
              expect(keymapManager.findKeyBindings(command: 'y').length).toBe 1
              expect(keymapManager.findKeyBindings(command: 'z').length).toBe 1

          it "reloads the file's key bindings and notifies ::onDidReloadKeymap observers with the keymap path even if the file is empty", ->
            fs.writeFileSync keymapFilePath, ""

            waitsFor 300, (done) ->
              keymapManager.onDidReloadKeymap (event) ->
                expect(event.path).toBe keymapFilePath
                done()

            runs ->
              expect(keymapManager.getKeyBindings().length).toBe 0

          it "reloads the file's key bindings and notifies ::onDidReloadKeymap observers with the keymap path even if the file has only comments", ->
            fs.writeFileSync keymapFilePath, """
            #  '.a': 'ctrl-a': 'y'
            #  '.b': 'ctrl-b': 'z'
            """

            waitsFor 300, (done) ->
              keymapManager.onDidReloadKeymap (event) ->
                expect(event.path).toBe keymapFilePath
                done()

            runs ->
              expect(keymapManager.getKeyBindings().length).toBe 0

          it "emits an event, logs a warning and does not reload if there is a problem reloading the file", ->
            didFailSpy = jasmine.createSpy()
            keymapManager.onDidFailToReadFile(didFailSpy)
            spyOn(console, 'warn')
            fs.writeFileSync keymapFilePath, "junk1."
            waitsFor 300, ->
              didFailSpy.callCount > 0
              console.warn.callCount > 0

            runs ->
              expect(keymapManager.findKeyBindings(command: 'x').length).toBe 1

        describe "when the file is removed", ->
          it "removes the bindings and notifies ::onDidUnloadKeymap observers with keymap path", ->
            jasmine.unspy(global, 'setTimeout')
            fs.removeSync(keymapFilePath)

            waitsFor 300, (done) ->
              keymapManager.onDidUnloadKeymap (event) ->
                expect(event.path).toBe keymapFilePath
                done()

            runs ->
              expect(keymapManager.findKeyBindings(command: 'x').length).toBe 0

        describe "when the file is moved", ->
          it "removes the bindings", ->
            jasmine.unspy(global, 'setTimeout')
            newFilePath = path.join(temp.mkdirSync('keymap-manager-spec'), "other-guy.cson")
            fs.moveSync(keymapFilePath, newFilePath)

            waitsFor 300, (done) ->
              keymapManager.onDidUnloadKeymap (event) ->
                expect(event.path).toBe keymapFilePath
                done()

            runs ->
              expect(keymapManager.findKeyBindings(command: 'x').length).toBe 0

        it "allows the watch to be cancelled via the returned subscription", ->
          subscription.dispose()
          fs.writeFileSync keymapFilePath, """
            '.a': 'ctrl-a': 'y'
            '.b': 'ctrl-b': 'z'
          """

          reloaded = false
          keymapManager.onDidReloadKeymap -> reloaded = true

          waits 300
          runs ->
            expect(reloaded).toBe false

          # Can start watching again after cancelling
          runs ->
            keymapManager.loadKeymap(keymapFilePath, watch: true)
            fs.writeFileSync keymapFilePath, """
              '.a': 'ctrl-a': 'q'
            """

          waitsFor 300, (done) ->
            keymapManager.onDidReloadKeymap(done)

          runs ->
            expect(keymapManager.findKeyBindings(command: 'q').length).toBe 1

    describe "if called with a directory path", ->
      it "loads all platform compatible keybindings files in the directory", ->
        spyOn(keymapManager, 'getOtherPlatforms').andReturn ['os2']
        keymapManager.loadKeymap(path.join(__dirname, 'fixtures'))
        expect(keymapManager.findKeyBindings(command: 'x').length).toBe 1
        expect(keymapManager.findKeyBindings(command: 'y').length).toBe 1
        expect(keymapManager.findKeyBindings(command: 'z').length).toBe 1
        expect(keymapManager.findKeyBindings(command: 'X').length).toBe 0
        expect(keymapManager.findKeyBindings(command: 'Y').length).toBe 0

  describe "events", ->
    it "emits `matched` when a key binding matches an event", ->
      handler = jasmine.createSpy('matched')
      keymapManager.onDidMatchBinding handler
      keymapManager.add "test",
        "body":
          "ctrl-x": "used-command"
        "*":
          "ctrl-x": "unused-command"
        ".not-in-the-dom":
          "ctrl-x": "unmached-command"

      keymapManager.handleKeyboardEvent(buildKeydownEvent('x', ctrl: true, target: document.body))
      expect(handler).toHaveBeenCalled()

      {keystrokes, binding, keyboardEventTarget} = handler.argsForCall[0][0]
      expect(keystrokes).toBe 'ctrl-x'
      expect(binding.command).toBe 'used-command'
      expect(keyboardEventTarget).toBe document.body

    it "emits `matched-partially` when a key binding partially matches an event", ->
      handler = jasmine.createSpy('matched-partially handler')
      keymapManager.onDidPartiallyMatchBindings handler
      keymapManager.add "test",
        "body":
          "ctrl-x 1": "command-1"
          "ctrl-x 2": "command-2"
          "a c ^c ^a": "command-3"

      keymapManager.handleKeyboardEvent(buildKeydownEvent('x', ctrl: true, target: document.body))
      expect(handler).toHaveBeenCalled()

      {keystrokes, partiallyMatchedBindings, keyboardEventTarget} = handler.argsForCall[0][0]
      expect(keystrokes).toBe 'ctrl-x'
      expect(partiallyMatchedBindings).toHaveLength 2
      expect(partiallyMatchedBindings.map ({command}) -> command).toEqual ['command-1', 'command-2']
      expect(keyboardEventTarget).toBe document.body

    it "emits `matched-partially` when a key binding that contains keyup keystrokes partially matches an event", ->
      handler = jasmine.createSpy('matched-partially handler')
      keymapManager.onDidPartiallyMatchBindings handler
      keymapManager.add "test",
        "body":
          "a c ^c ^a": "command-1"

      keymapManager.handleKeyboardEvent(buildKeydownEvent('a', target: document.body))
      keymapManager.handleKeyboardEvent(buildKeydownEvent('c', target: document.body))
      expect(handler).toHaveBeenCalled()

      {keystrokes, partiallyMatchedBindings, keyboardEventTarget} = handler.argsForCall[0][0]
      expect(keystrokes).toBe 'a'

      {keystrokes, partiallyMatchedBindings, keyboardEventTarget} = handler.argsForCall[1][0]
      expect(keystrokes).toBe 'a c'
      expect(partiallyMatchedBindings).toHaveLength 1
      expect(partiallyMatchedBindings.map ({command}) -> command).toEqual ['command-1']
      expect(keyboardEventTarget).toBe document.body

      handler.reset()
      keymapManager.handleKeyboardEvent(buildKeyupEvent('c', target: document.body))
      expect(handler).toHaveBeenCalled()

      {keystrokes, partiallyMatchedBindings, keyboardEventTarget} = handler.argsForCall[0][0]
      expect(keystrokes).toBe 'a c ^c'
      expect(partiallyMatchedBindings).toHaveLength 1
      expect(partiallyMatchedBindings.map ({command}) -> command).toEqual ['command-1']
      expect(keyboardEventTarget).toBe document.body

    it "emits `match-failed` when no key bindings match the event", ->
      handler = jasmine.createSpy('match-failed handler')
      keymapManager.onDidFailToMatchBinding handler
      keymapManager.add "test",
        "body":
          "ctrl-x": "command"

      keymapManager.handleKeyboardEvent(buildKeydownEvent('y', ctrl: true, target: document.body))
      expect(handler).toHaveBeenCalled()

      {keystrokes, keyboardEventTarget} = handler.argsForCall[0][0]
      expect(keystrokes).toBe 'ctrl-y'
      expect(keyboardEventTarget).toBe document.body
