/* global beforeEach, afterEach */

'use strict'

const lolex = require('lolex')
const sinon = require('sinon')

let sinonSandbox, fakeClock

beforeEach(function () {
  document.body.innerHTML = ''
  sinonSandbox = sinon.sandbox.create()
  fakeClock = lolex.install()
})

afterEach(function () {
  fakeClock.uninstall()
  sinonSandbox.restore()
})

exports.appendContent = function appendContent (element) {
  document.body.appendChild(element)
  return element
}

exports.stub = function stub () {
  return sinonSandbox.stub(...arguments)
}

exports.getFakeClock = function getFakeClock () {
  return fakeClock
}
