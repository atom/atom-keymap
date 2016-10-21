/** @babel */
/* eslint-env mocha */
/* global assert */

const PartialKeyupMatcher = require('../src/partial-keyup-matcher.js')
import {KeyBinding} from '../src/key-binding'

describe('PartialKeyupMatcher', () => {
  let matcher = new PartialKeyupMatcher()

  it('returns a simple single-modifier-keyup match', () => {
    const kb = keyBindingArgHelper('ctrl-tab ^ctrl')
    matcher.addPendingMatch(kb)
    const matches = matcher.getMatches('^ctrl')
    assert.equal(matches.length, 1)
    assert.equal(matches[0], kb)
  })
})

function keyBindingArgHelper (binding) {
  return new KeyBinding('test', 'test', binding, 'body', 0)
}
