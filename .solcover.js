module.exports = {
  skipFiles: ['mocks/', 'interfaces/'],
  configureYulOptimizer: true,
  measureStatementCoverage: true,
  measureFunctionCoverage: true,
  mocha: {
    grep: "@skip-on-coverage",
    invert: true
  }
}
