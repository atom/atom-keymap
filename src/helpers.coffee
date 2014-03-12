[parser, fs, loophole, pegjs] = []

Modifiers = new Set
Modifiers.add 'ctrl'
Modifiers.add 'alt'
Modifiers.add 'shift'
Modifiers.add 'cmd'

exports.normalizeKeystrokeSequence = (keystrokeSequence) ->
  keystrokeSequence.split(/\s+/)
    .map (keystroke) -> normalizeKeystroke(keystroke)
    .join(' ')

normalizeKeystroke = (keystroke) ->
  keys = parseKeystroke(keystroke)
  primaryKey = null
  modifiers = new Set

  for key in keys
    if Modifiers.has(key)
      modifiers.add(key)
    else
      primaryKey = key

  modifiers.add('shift') if /^[A-Z]$/.test(primaryKey)
  primaryKey = primaryKey.toUpperCase() if modifiers.has('shift') and /^[a-z]$/.test(primaryKey)

  keystroke = []
  keystroke.push('ctrl') if modifiers.has('ctrl')
  keystroke.push('alt') if modifiers.has('alt')
  keystroke.push('shift') if modifiers.has('shift')
  keystroke.push('cmd') if modifiers.has('cmd')
  keystroke.push(primaryKey) if primaryKey?
  keystroke.join('-')

parseKeystroke = (keystroke) ->
  unless parser?
    try
      parser = require './keystroke'
    catch
      fs ?= require 'fs'
      loophole ?= require 'loophole'
      pegjs ?= require 'pegjs'
      keystrokeGrammar = fs.readFileSync(require.resolve('./keystroke.pegjs'), 'utf8')
      loophole.allowUnsafeEval => parser = pegjs.buildParser(keystrokeGrammar)

  parser.parse(keystroke)
