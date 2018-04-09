const assert = require('assert');
const HDWalletProvider = require('truffle-hdwallet-provider');
const Web3 = require('web3');

const provider = new HDWalletProvider(
    'sauce reflect hawk shine keen into unusual liar syrup sheriff year slush',
    'https://rinkeby.infura.io/O65ePQFhZHcnWDRsE1hl'
);
const web3 = new Web3(provider);
const { interface, bytecode} = require('./subchainProtocolBase.export')

let accounts;
let contract;
let PROTOCAL = 'protocol 1.0';
let BOND_MIN = 10;

const deploy = async () => {
    accounts = await web3.eth.getAccounts();
    contract = await new web3.eth.Contract(JSON.parse(interface))
        .deploy({data: bytecode, arguments: [PROTOCAL, BOND_MIN]})
        .send({from: accounts[0], gas: '3000000'});
    contract.setProvider(provider);

    console.log('contract deployed to: ', contract.options.address);
}

deploy();
