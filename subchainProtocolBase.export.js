const fs = require('fs');
const solc = require('solc');

const path ='SubChainProtocolBase.sol';
const source = fs.readFileSync(path, 'utf8');

var input = {};
input[path] = source;

module.exports = solc.compile({sources: input}, 1).contracts['SubChainProtocolBase.sol:SubChainProtocolBase'];
