path = require 'path'
fs = require 'fs-plus'
temp = require 'temp'
{$$} = require 'space-pencil'
{appendContent} = require './spec-helper'
KeymapManager = require '../src/keymap-manager'
{keydownEvent} = KeymapManager

describe "KeymapManager", ->
  keymapManager = null

  beforeEach ->
    keymapManager = new KeymapManager

  afterEach ->
    keymapManager.destroy()

  describe "::handleKeyboardEvent(event)", ->
    describe "when the keystroke matches no bindings", ->
      it "does not prevent the event's default action", ->
        event = keydownEvent('q')
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

        keymapManager.addKeymap "test",
          ".a":
            "ctrl-x": "x-command"
            "ctrl-y": "y-command"
          ".c":
            "ctrl-y": "z-command"
          ".b":
            "ctrl-y": "y-command"

      it "dispatches the matching binding's command event on the keyboard event's target", ->
        keymapManager.handleKeyboardEvent(keydownEvent('y', ctrl: true, target: elementB))
        expect(events.length).toBe 1
        expect(events[0].type).toBe 'y-command'
        expect(events[0].target).toBe elementB

        events = []
        keymapManager.handleKeyboardEvent(keydownEvent('x', ctrl: true, target: elementB))
        expect(events.length).toBe 1
        expect(events[0].type).toBe 'x-command'
        expect(events[0].target).toBe elementB

      it "prevents the default action", ->
        event = keydownEvent('y', ctrl: true, target: elementB)
        keymapManager.handleKeyboardEvent(event)
        expect(event.defaultPrevented).toBe true

      describe "if .abortKeyBinding() is called on the command event", ->
        it "proceeds directly to the next matching binding and does not prevent the keyboard event's default action", ->
          elementB.addEventListener 'y-command', (e) -> events.push(e); e.abortKeyBinding()
          elementB.addEventListener 'y-command', (e) -> events.push(e) # should never be called
          elementB.addEventListener 'z-command', (e) -> events.push(e); e.abortKeyBinding()

          event = keydownEvent('y', ctrl: true, target: elementB)
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
          keymapManager.handleKeyboardEvent(keydownEvent('y', ctrl: true, target: document.body))
          expect(events.length).toBe 1
          expect(events[0].type).toBe 'y-command'
          expect(events[0].target).toBe elementA

      describe "if the matching binding's command is 'native!'", ->
        it "terminates without preventing the browser's default action", ->
          keymapManager.addKeymap "test",
            ".b":
              "ctrl-y": "native!"
          elementA.addEventListener 'native!', (e) -> events.push(e)

          event = keydownEvent('y', ctrl: true, target: elementB)
          keymapManager.handleKeyboardEvent(event)
          expect(events).toEqual []
          expect(event.defaultPrevented).toBe false

      describe "if the matching binding's command is 'unset!'", ->
        it "continues searching for a matching binding on the parent element", ->
          keymapManager.addKeymap "test",
            ".a":
              "ctrl-y": "x-command"
            ".b":
              "ctrl-y": "unset!"

          event = keydownEvent('y', ctrl: true, target: elementB)
          keymapManager.handleKeyboardEvent(event)
          expect(events.length).toBe 1
          expect(events[0].type).toBe 'x-command'
          expect(event.defaultPrevented).toBe true

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

      describe "when the bindings have selectors with different specificity", ->
        beforeEach ->
          keymapManager.addKeymap "test",
            ".b.c":
              "ctrl-x": "command-1"
            ".b":
              "ctrl-x": "command-2"

        it "dispatches the command associated with the most specific binding", ->
          keymapManager.handleKeyboardEvent(keydownEvent('x', ctrl: true, target: elementB))
          expect(events.length).toBe 1
          expect(events[0].type).toBe 'command-1'
          expect(events[0].target).toBe elementB

      describe "when the bindings have selectors with the same specificity", ->
        beforeEach ->
          keymapManager.addKeymap "test",
            ".b.c":
              "ctrl-x": "command-1"
            ".c.d":
              "ctrl-x": "command-2"

        it "dispatches the command associated with the most recently added binding", ->
          keymapManager.handleKeyboardEvent(keydownEvent('x', ctrl: true, target: elementB))
          expect(events.length).toBe 1
          expect(events[0].type).toBe 'command-2'
          expect(events[0].target).toBe elementB

    describe "when the keystroke partially matches bindings", ->
      [workspace, editor, events] = []

      beforeEach ->
        workspace = appendContent $$ ->
          @div class: 'workspace', ->
            @div class: 'editor'
        editor = workspace.firstChild

        keymapManager.addKeymap 'test',
          '.workspace':
            'd o g': 'dog'
            'v i v a': 'viva!'
            'v i v': 'viv'
          '.editor': 'v': 'enter-visual-mode'
          '.editor.visual-mode': 'i w': 'select-inside-word'

        events = []
        workspace.addEventListener 'dog', -> events.push('dog')
        workspace.addEventListener 'viva!', -> events.push('viva!')
        workspace.addEventListener 'viv', -> events.push('viv')
        workspace.addEventListener 'select-inside-word', -> events.push('select-inside-word')
        workspace.addEventListener 'enter-visual-mode', -> events.push('enter-visual-mode'); editor.classList.add('visual-mode')

      describe "when subsequent keystrokes yield an exact match", ->
        it "dispatches the command associated with the matched multi-keystroke binding", ->
          keymapManager.handleKeyboardEvent(keydownEvent('v', target: editor))
          keymapManager.handleKeyboardEvent(keydownEvent('i', target: editor))
          keymapManager.handleKeyboardEvent(keydownEvent('v', target: editor))
          keymapManager.handleKeyboardEvent(keydownEvent('a', target: editor))
          expect(events).toEqual ['viva!']

      describe "when subsequent keystrokes yield no matches", ->
        it "disables the bindings with the longest keystroke sequences and replays the queued keystrokes", ->
          keymapManager.handleKeyboardEvent(vEvent = keydownEvent('v', target: editor))
          keymapManager.handleKeyboardEvent(iEvent = keydownEvent('i', target: editor))
          keymapManager.handleKeyboardEvent(wEvent = keydownEvent('w', target: editor))
          expect(vEvent.defaultPrevented).toBe true
          expect(iEvent.defaultPrevented).toBe true
          expect(wEvent.defaultPrevented).toBe true
          expect(events).toEqual ['enter-visual-mode', 'select-inside-word']

          events = []
          keymapManager.handleKeyboardEvent(vEvent = keydownEvent('v', target: editor))
          keymapManager.handleKeyboardEvent(iEvent = keydownEvent('i', target: editor))
          keymapManager.handleKeyboardEvent(kEvent = keydownEvent('k', target: editor))
          expect(vEvent.defaultPrevented).toBe true
          expect(iEvent.defaultPrevented).toBe true
          expect(kEvent.defaultPrevented).toBe false
          expect(events).toEqual ['enter-visual-mode']
          expect(clearTimeout).toHaveBeenCalled()

      describe "when the currently queued keystrokes exactly match at least one binding", ->
        it "disables partially-matching bindings and replays the queued keystrokes if the ::partialMatchTimeout expires", ->
          keymapManager.handleKeyboardEvent(keydownEvent('v', target: editor))
          expect(events).toEqual []
          advanceClock(keymapManager.partialMatchTimeout)
          expect(events).toEqual ['enter-visual-mode']

          events = []
          keymapManager.handleKeyboardEvent(keydownEvent('v', target: editor))
          keymapManager.handleKeyboardEvent(keydownEvent('i', target: editor))
          expect(events).toEqual []
          advanceClock(keymapManager.partialMatchTimeout)
          expect(events).toEqual ['enter-visual-mode']

          events = []
          keymapManager.handleKeyboardEvent(keydownEvent('v', target: editor))
          keymapManager.handleKeyboardEvent(keydownEvent('i', target: editor))
          keymapManager.handleKeyboardEvent(keydownEvent('v', target: editor))
          expect(events).toEqual []
          advanceClock(keymapManager.partialMatchTimeout)
          expect(events).toEqual ['viv']

        it "does not enter a pending state or prevent the default action if the matching binding's command is 'native!'", ->
          keymapManager.addKeymap 'test', '.workspace': 'v': 'native!'
          event = keydownEvent('v', target: editor)
          keymapManager.handleKeyboardEvent(event)
          expect(event.defaultPrevented).toBe false
          expect(global.setTimeout).not.toHaveBeenCalled()
          expect(keymapManager.queuedKeyboardEvents.length).toBe 0

      describe "when the currently queued keystrokes don't exactly match any bindings", ->
        it "never times out of the pending state", ->
          keymapManager.handleKeyboardEvent(keydownEvent('d', target: editor))
          keymapManager.handleKeyboardEvent(keydownEvent('o', target: editor))

          advanceClock(keymapManager.partialMatchTimeout)
          advanceClock(keymapManager.partialMatchTimeout)

          expect(events).toEqual []
          keymapManager.handleKeyboardEvent(keydownEvent('g', target: editor))
          expect(events).toEqual ['dog']

    it "only counts entire keystrokes when checking for partial matches", ->
      element = $$ -> @div class: 'a'
      keymapManager.addKeymap 'test',
        '.a':
          'ctrl-alt-a': 'command-a'
          'ctrl-a': 'command-b'
      events = []
      element.addEventListener 'command-a', -> events.push('command-a')
      element.addEventListener 'command-b', -> events.push('command-b')

      # Should *only* match ctrl-a, not ctrl-alt-a (can't just use a textual prefix match)
      keymapManager.handleKeyboardEvent(keydownEvent('a', ctrl: true, target: element))
      expect(events).toEqual ['command-b']

    it "does not enqueue keydown events consisting only of modifier keys", ->
      element = $$ -> @div class: 'a'
      keymapManager.addKeymap 'test', '.a': 'ctrl-a ctrl-b': 'command'
      events = []
      element.addEventListener 'command', -> events.push('command')

      # Simulate keydown events for the modifier key being pressed on its own
      # prior to the key it is modifying.
      keymapManager.handleKeyboardEvent(keydownEvent('ctrl', target: element))
      keymapManager.handleKeyboardEvent(keydownEvent('a', ctrl: true, target: element))
      keymapManager.handleKeyboardEvent(keydownEvent('ctrl', target: element))
      keymapManager.handleKeyboardEvent(keydownEvent('b', ctrl: true, target: element))

      expect(events).toEqual ['command']

    it "allows solo modifier-keys to be bound", ->
      element = $$ -> @div class: 'a'
      keymapManager.addKeymap 'test', '.a': 'ctrl': 'command'
      events = []
      element.addEventListener 'command', -> events.push('command')

      keymapManager.handleKeyboardEvent(keydownEvent('ctrl', target: element))
      expect(events).toEqual ['command']

    it "simulates bubbling if the target is detached", ->
      elementA = $$ ->
        @div class: 'a', ->
          @div class: 'b', ->
            @div class: 'c'
      elementB = elementA.firstChild
      elementC = elementB.firstChild

      keymapManager.addKeymap 'test', '.c': 'x': 'command'

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

      keymapManager.handleKeyboardEvent(keydownEvent('x', target: elementC))

      expect(events).toEqual ['c', 'b1']

  describe "::addKeymap(source, bindings)", ->
    it "normalizes keystrokes containing capitalized alphabetic characters", ->
      keymapManager.addKeymap 'test', '*': 'ctrl-shift-l': 'a'
      keymapManager.addKeymap 'test', '*': 'ctrl-shift-L': 'b'
      keymapManager.addKeymap 'test', '*': 'ctrl-L': 'c'
      expect(keymapManager.findKeyBindings(command: 'a')[0].keystrokes).toBe 'ctrl-shift-L'
      expect(keymapManager.findKeyBindings(command: 'b')[0].keystrokes).toBe 'ctrl-shift-L'
      expect(keymapManager.findKeyBindings(command: 'c')[0].keystrokes).toBe 'ctrl-shift-L'

    it "normalizes the order of modifier keys based on the Apple interface guidelines", ->
      keymapManager.addKeymap 'test', '*': 'alt-cmd-ctrl-shift-l': 'a'
      keymapManager.addKeymap 'test', '*': 'shift-ctrl-l': 'b'
      keymapManager.addKeymap 'test', '*': 'alt-ctrl-l': 'c'
      keymapManager.addKeymap 'test', '*': 'ctrl-alt--': 'd'

      expect(keymapManager.findKeyBindings(command: 'a')[0].keystrokes).toBe 'ctrl-alt-shift-cmd-L'
      expect(keymapManager.findKeyBindings(command: 'b')[0].keystrokes).toBe 'ctrl-shift-L'
      expect(keymapManager.findKeyBindings(command: 'c')[0].keystrokes).toBe 'ctrl-alt-l'
      expect(keymapManager.findKeyBindings(command: 'd')[0].keystrokes).toBe 'ctrl-alt--'

    it "rejects bindings with unknown modifier keys and logs a warning to the console", ->
      spyOn(console, 'warn')
      keymapManager.addKeymap 'test', '*': 'meta-shift-A': 'a'
      expect(console.warn).toHaveBeenCalled()

      event = keydownEvent('A', shift: true, target: document.body)
      keymapManager.handleKeyboardEvent(event)
      expect(event.defaultPrevented).toBe false

  describe "::removeKeymap(source)", ->
    it "removes all bindings originating from the given source", ->
      keymapManager.addKeymap 'foo',
        '.a':
          'ctrl-a': 'x'
        '.b':
          'ctrl-b': 'y'

      keymapManager.addKeymap 'bar',
        '.c':
          'ctrl-c': 'z'

      expect(keymapManager.findKeyBindings(command: 'x').length).toBe 1
      expect(keymapManager.findKeyBindings(command: 'y').length).toBe 1
      expect(keymapManager.findKeyBindings(command: 'z').length).toBe 1

      keymapManager.removeKeymap('bar')

      expect(keymapManager.findKeyBindings(command: 'x').length).toBe 1
      expect(keymapManager.findKeyBindings(command: 'y').length).toBe 1
      expect(keymapManager.findKeyBindings(command: 'z').length).toBe 0

  describe "::keystrokeForKeyboardEvent(event)", ->
    describe "when no modifiers are pressed", ->
      it "returns a string that identifies the unmodified keystroke", ->
        expect(keymapManager.keystrokeForKeyboardEvent(keydownEvent('a'))).toBe 'a'
        expect(keymapManager.keystrokeForKeyboardEvent(keydownEvent('['))).toBe '['
        expect(keymapManager.keystrokeForKeyboardEvent(keydownEvent('*'))).toBe '*'
        expect(keymapManager.keystrokeForKeyboardEvent(keydownEvent('left'))).toBe 'left'
        expect(keymapManager.keystrokeForKeyboardEvent(keydownEvent('\b'))).toBe 'backspace'

    describe "when a modifier key is combined with a non-modifier key", ->
      it "returns a string that identifies the modified keystroke", ->
        expect(keymapManager.keystrokeForKeyboardEvent(keydownEvent('a', alt: true))).toBe 'alt-a'
        expect(keymapManager.keystrokeForKeyboardEvent(keydownEvent('[', cmd: true))).toBe 'cmd-['
        expect(keymapManager.keystrokeForKeyboardEvent(keydownEvent('*', ctrl: true))).toBe 'ctrl-*'
        expect(keymapManager.keystrokeForKeyboardEvent(keydownEvent('left', ctrl: true, alt: true, cmd: true))).toBe 'ctrl-alt-cmd-left'
        expect(keymapManager.keystrokeForKeyboardEvent(keydownEvent('A', shift: true))).toBe 'shift-A'
        expect(keymapManager.keystrokeForKeyboardEvent(keydownEvent('{', shift: true))).toBe '{'
        expect(keymapManager.keystrokeForKeyboardEvent(keydownEvent('left', shift: true))).toBe 'shift-left'
        expect(keymapManager.keystrokeForKeyboardEvent(keydownEvent('Left', shift: true))).toBe 'shift-left'

    describe "when a non-English keyboard language is used", ->
      it "uses the physical character pressed instead of the character it maps to in the current language", ->
        expect(keymapManager.keystrokeForKeyboardEvent(keydownEvent('U+03B6', cmd: true, which: 122))).toBe 'cmd-z'

    describe "on Linux", ->
      originalPlatform = null

      beforeEach ->
        originalPlatform = process.platform
        Object.defineProperty process, 'platform', value: 'linux'

      afterEach ->
        Object.defineProperty process, 'platform', value: originalPlatform

      it "corrects a Chromium bug where the keyIdentifier is incorrect for certain keypress events", ->
        expect(keymapManager.keystrokeForKeyboardEvent(keydownEvent('U+00ba', ctrl: true))).toBe 'ctrl-;'
        expect(keymapManager.keystrokeForKeyboardEvent(keydownEvent('U+00bb', ctrl: true))).toBe 'ctrl-='
        expect(keymapManager.keystrokeForKeyboardEvent(keydownEvent('U+00bc', ctrl: true))).toBe 'ctrl-,'
        expect(keymapManager.keystrokeForKeyboardEvent(keydownEvent('U+00bd', ctrl: true))).toBe 'ctrl--'
        expect(keymapManager.keystrokeForKeyboardEvent(keydownEvent('U+00be', ctrl: true))).toBe 'ctrl-.'
        expect(keymapManager.keystrokeForKeyboardEvent(keydownEvent('U+00bf', ctrl: true))).toBe 'ctrl-/'
        expect(keymapManager.keystrokeForKeyboardEvent(keydownEvent('U+00db', ctrl: true))).toBe 'ctrl-['
        expect(keymapManager.keystrokeForKeyboardEvent(keydownEvent('U+00dc', ctrl: true))).toBe 'ctrl-\\'
        expect(keymapManager.keystrokeForKeyboardEvent(keydownEvent('U+00dd', ctrl: true))).toBe 'ctrl-]'
        expect(keymapManager.keystrokeForKeyboardEvent(keydownEvent('U+00de', ctrl: true))).toBe 'ctrl-\''

      it "always includes the shift modifier in the keystroke", ->
        expect(keymapManager.keystrokeForKeyboardEvent(keydownEvent('9', ctrl: true, shift: true))).toBe 'ctrl-shift-9'
        expect(keymapManager.keystrokeForKeyboardEvent(keydownEvent('/', ctrl: true, shift: true))).toBe 'ctrl-shift-/'
        expect(keymapManager.keystrokeForKeyboardEvent(keydownEvent('a', ctrl: true, shift: true))).toBe 'ctrl-shift-A'

  describe "::findKeyBindings({command, target, keystrokes})", ->
    [elementA, elementB] = []
    beforeEach ->
      elementA = appendContent $$ ->
        @div class: 'a', ->
          @div class: 'b c'
          @div class: 'd'
      elementB = elementA.querySelector('.b.c')

      keymapManager.addKeymap 'test',
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
          subscription = keymapManager.loadKeymap(keymapFilePath, watch: true)
          expect(keymapManager.findKeyBindings(command: 'x').length).toBe 1

        describe "when the file is changed", ->
          it "reloads the file's key bindings and emits 'reloaded-key-bindings' with the path", ->
            fs.writeFileSync keymapFilePath, """
              '.a': 'ctrl-a': 'y'
              '.b': 'ctrl-b': 'z'
            """

            waitsFor 300, (done) ->
              keymapManager.once 'reloaded-key-bindings', (filePath) ->
                expect(filePath).toBe keymapFilePath
                done()

            runs ->
              expect(keymapManager.findKeyBindings(command: 'x').length).toBe 0
              expect(keymapManager.findKeyBindings(command: 'y').length).toBe 1
              expect(keymapManager.findKeyBindings(command: 'z').length).toBe 1

          it "logs a warning and does not reload if there is a problem reloading the file", ->
            spyOn(console, 'warn')
            fs.writeFileSync keymapFilePath, "junk1."
            waitsFor 300, -> console.warn.callCount > 0

            runs ->
              expect(keymapManager.findKeyBindings(command: 'x').length).toBe 1

        describe "when the file is removed", ->
          it "removes the bindings and emits 'unloaded-key-bindings' with the path", ->
            jasmine.unspy(global, 'setTimeout')
            fs.removeSync(keymapFilePath)

            waitsFor 300, (done) ->
              keymapManager.once 'unloaded-key-bindings', (filePath) ->
                expect(filePath).toBe keymapFilePath
                done()

            runs ->
              expect(keymapManager.findKeyBindings(command: 'x').length).toBe 0

        describe "when the file is moved", ->
          it "removes the bindings", ->
            jasmine.unspy(global, 'setTimeout')
            newFilePath = path.join(temp.mkdirSync('keymap-manager-spec'), "other-guy.cson")
            fs.moveSync(keymapFilePath, newFilePath)

            waitsFor 300, (done) ->
              keymapManager.once 'unloaded-key-bindings', (filePath) ->
                expect(filePath).toBe keymapFilePath
                done()

            runs ->
              expect(keymapManager.findKeyBindings(command: 'x').length).toBe 0

        it "allows the watch to be cancelled via the returned subscription", ->
          subscription.off()
          fs.writeFileSync keymapFilePath, """
            '.a': 'ctrl-a': 'y'
            '.b': 'ctrl-b': 'z'
          """

          reloaded = false
          keymapManager.on 'reloaded-key-bindings', -> reloaded = true

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
            keymapManager.once 'reloaded-key-bindings', done

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
      keymapManager.on 'matched', handler
      keymapManager.addKeymap "test",
        "body":
          "ctrl-x": "used-command"
        "*":
          "ctrl-x": "unused-command"
        ".not-in-the-dom":
          "ctrl-x": "unmached-command"

      keymapManager.handleKeyboardEvent(keydownEvent('x', ctrl: true, target: document.body))
      expect(handler).toHaveBeenCalled()

      {keystrokes, binding, keyboardEventTarget} = handler.argsForCall[0][0]
      expect(keystrokes).toBe 'ctrl-x'
      expect(binding.command).toBe 'used-command'
      expect(keyboardEventTarget).toBe document.body

    it "emits `matched-partially` when a key binding partially matches an event", ->
      handler = jasmine.createSpy('matched-partially handler')
      keymapManager.on 'matched-partially', handler
      keymapManager.addKeymap "test",
        "body":
          "ctrl-x 1": "command-1"
          "ctrl-x 2": "command-2"

      keymapManager.handleKeyboardEvent(keydownEvent('x', ctrl: true, target: document.body))
      expect(handler).toHaveBeenCalled()

      {keystrokes, partiallyMatchedBindings, keyboardEventTarget} = handler.argsForCall[0][0]
      expect(keystrokes).toBe 'ctrl-x'
      expect(partiallyMatchedBindings).toHaveLength 2
      expect(partiallyMatchedBindings.map ({command}) -> command).toEqual ['command-1', 'command-2']
      expect(keyboardEventTarget).toBe document.body

    it "emits `match-failed` when no key bindings match the event", ->
      handler = jasmine.createSpy('match-failed handler')
      keymapManager.on 'match-failed', handler
      keymapManager.addKeymap "test",
        "body":
          "ctrl-x": "command"

      keymapManager.handleKeyboardEvent(keydownEvent('y', ctrl: true, target: document.body))
      expect(handler).toHaveBeenCalled()

      {keystrokes, keyboardEventTarget} = handler.argsForCall[0][0]
      expect(keystrokes).toBe 'ctrl-y'
      expect(keyboardEventTarget).toBe document.body
