require 'coffee-cache'

beforeEach ->
  document.querySelector('#jasmine-content').innerHTML = ""

exports.appendContent = (element) ->
  document.querySelector('#jasmine-content').appendChild(element)
  element
