require('babel-register')
require('coffee-script/register')

global.assert = require('chai').assert

if (process.env.SUPPRESS_EXIT) {
  process.exit = function (code) {}
}
