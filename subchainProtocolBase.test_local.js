const ganache = require('ganache-cli');
const assert = require('assert');
const Web3 = require('web3');

const provider = ganache.provider();
const web3 = new Web3(provider);
const { interface, bytecode } = require('./subchainProtocolBase.export');

// moache
// beforeEach, describe, it

let accounts;
let contract;

beforeEach(async () => {
    accounts = await web3.eth.getAccounts();
    contract = await new web3.eth.Contract(JSON.parse(interface))
        .deploy({data: bytecode, arguments: ['1.0', 1]})
        .send({from: accounts[0], gas: '3000000'});

    contract.setProvider(provider);

});

describe('Moac test', () => {
    it('deploy contract', async () => {
        assert.ok(contract.options.address);
        console.log(contract.options.address);
        const protocol = await contract.methods.subChainProtocol().call();
        const bondMin = await contract.methods.bondMin().call();
        assert.equal('1.0', protocol);
        assert.equal(1, bondMin);
    });

    it('register for SCS successfully', async () => {
        await contract.methods.register(accounts[0]).send(
            {from: accounts[0], gas: '1000000', value: 2}
        );
        // check scs_count
        const scsCount = await contract.methods.scsCount().call();
        assert.equal(1, scsCount);

        // check scs
        const scs = await contract.methods.scsList(accounts[0]).call();
        assert.equal(1, scs.state);
        assert.equal(2, scs.bond);
        assert.equal(accounts[0], scs.from);

        // check contract
        const contractBalance = await web3.eth.getBalance(contract.options.address)
        assert.equal(2, contractBalance);
    });

    it('register for SCS failed', async () => {
        try {
            await contract.methods.register(accounts[0]).send(
                {from: accounts[0], gas: '1000000', value: 0.5}
            );
            assert(false);
        } catch (err) {
            assert(err);
        }
    });

    it('withdrawRequest for scs successfully', async () => {
        // register for scs
        for(i = 0; i < accounts.length; i++) {
            await contract.methods.register(accounts[i]).send(
                {from: accounts[i], gas: '1000000', value: 2}
            );
        }

        // check for scsCount
        var scsCount = await contract.methods.scsCount().call();
        assert.equal(scsCount, accounts.length);

        // assert UnRegistered event
        let UnRegisteredEmitted = false;
        contract.once(
            'UnRegistered',
            {fromBlock: 0, toBlock: 'latest'},
            (err, log) => {
                assert.equal(accounts[0], log.returnValues.sender);
                UnRegisteredEmitted = true;
            }
        );

        // withdrawRequest
        await contract.methods.withdrawRequest().send(
            {from: accounts[0], gas: '1000000'}
        );

        // check withdraw result
        assert.equal(true, UnRegisteredEmitted);
        const blocknumber = await web3.eth.getBlockNumber();
        const scs = await contract.methods.scsList(accounts[0]).call();
        assert.equal(blocknumber, scs.withdrawBlock);
        assert.equal(2, scs.state);
        scsCount = await contract.methods.scsCount().call();
        assert.equal(scsCount, accounts.length - 1);
    });

    // evm_mine
    it('check if scs is performing.', async () => {
        await contract.methods.register(accounts[0]).send(
            {from: accounts[0], gas: '1000000', value: 10}
        );

        // should be false because of pending block
        let isPerforming = await contract.methods.isPerforming(accounts[0]).call();
        assert.equal(false, isPerforming);

        // mine pending blocks
        const pending_block_delay = await contract.methods.PEDNING_BLOCK_DELAY().call();
        for(i = 0; i < pending_block_delay; i++) {
            await web3.currentProvider.send(
                {jsonrpc: "2.0", method: "evm_mine", params: [], id: 100},
                function(err, result) {}
            );
        }

        // should be true
        isPerforming = await contract.methods.isPerforming(accounts[0]).call();
        assert.equal(true, isPerforming);
    });
});
