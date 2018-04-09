pragma solidity ^0.4.11;
//David Chen
//Subchain definition for application.


contract SysContract {
    function delayedSend(uint _blk, address _to, uint256 _value, bool bonded) public returns (bool success);
}


contract SubChainProtocolBase {
    enum SCSStatus { notRegistered, performing, withdrawPending, initialPending, withdrawDone, inactive }

    struct SCS {
        address from; //address as id
        uint256 bond;   // value
        uint state; // one of SCSStatus
        uint256 registerBlock;
        uint256 withdrawBlock;
    }

    struct SCSApproval {
        uint bondApproved;
        uint bondedCount;
        address[] subchainAddr;
        uint[] amount;
    }

    mapping(address => SCS) public scsList;
    mapping(address => SCSApproval) public scsApprovalList;

    uint public scsCount;
    string public subChainProtocol;
    uint public bondMin;
    uint public constant PEDNING_BLOCK_DELAY = 50; // 8 minutes
    uint public constant WITHDRAW_BLOCK_DELAY = 8640; // one day, given 10s block rate
    SysContract internal constant SYS_CONTRACT = SysContract(0x0000000000000000000000000000000000000065);

    //events
    event Registered(address scs);
    event UnRegistered(address sender);

    //constructor
    function SubChainProtocolBase(string protocol, uint bmin) public {
        scsCount = 0;
        subChainProtocol = protocol;
        bondMin = bmin;
    }

    function() public payable {  // todo: david review
        revert();
    }

    // register for SCS
    // SCS will be notified through 3rd party communication method. SCS will need to register here manually.
    // One protocol base can have several different subchains.
    function register(address scs) public payable returns (bool) {
        //already registered or not enough bond
        require(
            (scsList[scs].state == uint(SCSStatus.notRegistered)
            || scsList[scs].state == uint(SCSStatus.inactive))
            && msg.value >= bondMin
        );

        scsList[scs].from = scs;
        scsList[scs].bond = msg.value;
        scsList[scs].state = uint(SCSStatus.performing);
        scsList[scs].registerBlock = block.number + PEDNING_BLOCK_DELAY;
        scsList[scs].withdrawBlock = 2 ** 256 - 1;
        scsCount++;
        return true;
    }

    function isPerforming(address _addr) public view returns (bool res) {
        return (scsList[_addr].state == uint(SCSStatus.performing) && scsList[_addr].registerBlock < block.number);
    }

    // withdrawRequest for SCS
    function withdrawRequest() public returns (bool success) {
        //only can withdraw when active
        require(scsList[msg.sender].state == uint(SCSStatus.performing));

        scsList[msg.sender].withdrawBlock = block.number;
        scsList[msg.sender].state = uint(SCSStatus.withdrawPending);
        scsCount--;

        UnRegistered(msg.sender);
        return true;
    }

    function withdraw() public {
        if (
            scsList[msg.sender].state == uint(SCSStatus.withdrawPending)
            && block.number > (scsList[msg.sender].withdrawBlock + WITHDRAW_BLOCK_DELAY)
        ) {
            scsList[msg.sender].state == uint(SCSStatus.withdrawDone);
            scsList[msg.sender].from.transfer(scsList[msg.sender].bond);
        }
    }

    function getSelectionTarget(uint thousandth, uint minnum) public view returns (uint target) {
        // find a target to choose thousandth/1000 of total scs
        if (minnum < 50) {
            minnum = 50;
        }

        if (scsCount < minnum) {          // or use scsCount* thousandth / 1000 + 1 < minnum
            return 255;
        }

        uint m = thousandth * scsCount / 1000;

        if (m < minnum) {
            m = minnum;
        }

        target = (m * 256 / scsCount + 1) / 2;

        return target;
    }

    //display approved scs list
    function approvalAddresses(address addr) public view returns (address[]) {
        address[] memory res = new address[](scsApprovalList[addr].bondedCount);
        for (uint i = 0; i < scsApprovalList[addr].bondedCount; i++) {
            res[i] = (scsApprovalList[addr].subchainAddr[i]);
        }
        return res;
    }

    //display approved amount array
    function approvalAmounts(address addr) public view returns (uint[]) {
        uint[] memory res = new uint[](scsApprovalList[addr].bondedCount);
        for (uint i = 0; i < scsApprovalList[addr].bondedCount; i++) {
            res[i] = (scsApprovalList[addr].amount[i]);
        }
        return res;
    }

    //approve the bond to be deduced if act maliciously
    function approveBond(address scs, uint amount, uint8 v, bytes32 r, bytes32 s) public returns (bool) {
        //make sure SCS is performing
        if (!isPerforming(scs)) {
            return false;
        }

        //verify signature
        //combine scs and subchain address
        bytes32 hash = sha256(scs, msg.sender);

        //verify signature matches.
        if (ecrecover(hash, v, r, s) != scs) {
            return false;
        }

        //check if bond still available for SCSApproval
        if (scsList[scs].bond < (scsApprovalList[scs].bondApproved + amount)) {
            return false;
        }

        //add subchain info
        scsApprovalList[scs].bondApproved += amount;
        scsApprovalList[scs].subchainAddr.push(msg.sender);
        scsApprovalList[scs].amount.push(amount);
        scsApprovalList[scs].bondedCount++;

        return true;
    }

    //must called from SubChainBase
    function forfeitBond(address scs, uint amount) public payable returns (bool) {
        //check if subchain is approved
        for (uint i = 0; i < scsApprovalList[scs].bondedCount; i++) {
            if (scsApprovalList[scs].subchainAddr[i] == msg.sender && scsApprovalList[scs].amount[i] == amount) {
                //delete array item by moving the last item in current postion and delete the last one
                scsApprovalList[scs].bondApproved -= amount;
                scsApprovalList[scs].bondedCount--;
                scsApprovalList[scs].subchainAddr[i]
                    = scsApprovalList[scs].subchainAddr[scsApprovalList[scs].bondedCount];
                scsApprovalList[scs].amount[i] = scsApprovalList[scs].amount[scsApprovalList[scs].bondedCount];

                delete scsApprovalList[scs].subchainAddr[scsApprovalList[scs].bondedCount];
                delete scsApprovalList[scs].amount[scsApprovalList[scs].bondedCount];
                scsApprovalList[scs].subchainAddr.length--;
                scsApprovalList[scs].amount.length--;

                //doing the deduction
                scsList[scs].bond -= amount;
                msg.sender.transfer(amount);

                return true;
            }
        }

        return false;
    }

    //user to request to release from a subchain
    function releaseBond(address scs, uint amount, uint8 v, bytes32 r, bytes32 s) public returns (bool) {
        //verify signature
        //combine scs and subchain address
        bytes32 hash = sha256(scs, msg.sender);

        //verify signature matches.
        if (ecrecover(hash, v, r, s) != scs) {
            return false;
        }

        //add subchain info
        for (uint i=0; i < scsApprovalList[scs].bondedCount; i++) {
            if (scsApprovalList[scs].subchainAddr[i] == msg.sender && scsApprovalList[scs].amount[i] == amount) {
                scsApprovalList[scs].bondApproved -= amount;
                scsApprovalList[scs].bondedCount--;
                scsApprovalList[scs].subchainAddr[i]
                    = scsApprovalList[scs].subchainAddr[scsApprovalList[scs].bondedCount];
                scsApprovalList[scs].amount[i] = scsApprovalList[scs].amount[scsApprovalList[scs].bondedCount];

                //clear
                delete scsApprovalList[scs].subchainAddr[scsApprovalList[scs].bondedCount];
                delete scsApprovalList[scs].amount[scsApprovalList[scs].bondedCount];
                scsApprovalList[scs].subchainAddr.length--;
                scsApprovalList[scs].amount.length--;

                break;
            }
        }
        return true;
    }
}
