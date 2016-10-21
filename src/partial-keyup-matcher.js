'use babel'

module.exports =
class PartialKeyupMatcher { // Ian TODO this name sucks

  constructor() {
    this._pendingMatches = new Set()
  }

  addPendingMatch(keyBinding) {
    this._pendingMatches.add(keyBinding)
    keyBinding['nextKeyUpIndex'] = 0
  }

  // Returns matching bindings(s) if any.
  // Updates state for next match.
  getMatches(keyupKeystroke) {
    let matches = []
    for (let keyBinding of this._pendingMatches) {
      let toMatch = keyBinding.getKeyups()[keyBinding['nextKeyUpIndex']]
      if (keyupKeystroke == toMatch) {
        if (keyBinding['nextKeyUpIndex'] == keyBinding.getKeyups().length-1) {
          // Full match. Remove and return it.
          this._pendingMatches.delete(keyBinding)
          matches.push(keyBinding)
        }
        else {
          // Partial match. Increment what we're looking for next.
          keyBinding['nextKeyUpIndex']++
        }
      }
    }
    return matches
  }

}
