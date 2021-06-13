// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

contract Randao {
    
    struct Participant {
        address participantAddr;
        uint256 secretNum;
        bytes32 secretHash;
        bool committed;
        bool revealedSecret;
        bool reward;
    }
    
    struct ConsensusGroup {
        uint256 bountyPot;
        uint256 numCommits;
        uint256 numValid;
        uint256 random;
        uint256 phaseTransitionDeadline;
        uint256 minParticipants;
        uint256 bat;
        bool done;
        mapping(address => Participant) participants;
    }
    
    address payable contractOwner;
    uint256 public numSessions;
    ConsensusGroup[1000] rngGroups;
    
    event onGroupCreated(address sender, uint256 ptd, uint256 mp);
    event onCommitToGroup(address committer, uint256 gid);
    event onReveal(address revealer, uint256 gid, bool revealValidation);
    event bountySplit(address requester, uint256 totalPot, uint256 split);
    event updateStat(uint256 gid, uint256 valid, uint256 commit);
    event onPay(address destination, uint256 val);

    constructor() {
        contractOwner = payable(msg.sender);
        numSessions = 0;
    }
    
    // Creates a new group and returns the group id.
    // adds payable to the bountyPot.
    function newRNGGroup(uint256 ptd, uint256 mp) external payable returns(uint256) {
        require(msg.value >= 1 ether, "Minimum of 1 ether required to create a RNG campaign");
        ConsensusGroup storage c = rngGroups[numSessions];
        c.phaseTransitionDeadline = ptd;
        c.minParticipants = mp;
        c.bat = block.number;
        c.bountyPot+=msg.value;
        c.numCommits = 0;
        c.numValid = 0;
        c.done = false;
        numSessions++;
        emit onGroupCreated(msg.sender, ptd, mp);
        return numSessions-1;
    }
    
    // Commit to the RNG group. This is payable.
    // If Reveal doesn't happen after commit, then eth wont be returned.
    function commitToGroup(uint256 gid, bytes32 hash) public payable returns(bool){
        require(msg.value >= 1 ether, "Minium of 1 ether required to commit to group");
        ConsensusGroup storage c = rngGroups[gid];
        require(!c.done, "C done");
        // Check if its in phaseTransitionDeadline
        require(block.number < (c.bat+ c.phaseTransitionDeadline), "Commit phase expired");
        // Hmm, take the last join to account.
        Participant storage p = c.participants[msg.sender];
        if(!p.committed){
            c.numCommits++;
        }
        // Take the last value sent.
        c.participants[msg.sender] = Participant(msg.sender, 0, hash, true, false, false);
        // Take all the balance into account to bountyPot anyway.
        c.bountyPot += msg.value;
        emit onCommitToGroup(msg.sender, gid);
        emit updateStat(gid, c.numCommits, c.numValid);
        return true;
    }
    
    // Reveal the Secret number.
    // Not payable.
    function revealPhase(uint256 gid, uint256 secret) public returns(bool) {
        // TODO: Proper state transition is not followed deliberately to manual test.
        ConsensusGroup storage c = rngGroups[gid];
        require(!c.done, "C done");
        require(block.number < (c.bat + 2*c.phaseTransitionDeadline), "Reveal phase done");
        Participant storage p= c.participants[msg.sender];
        require(p.committed && !p.revealedSecret, "Participant has not committed");
        p.revealedSecret = true;
        p.secretNum = secret;
        bool v = verifySecret(p.secretNum, p.secretHash);
        if(v){
            c.numValid++;
            c.random ^= secret;
        }else{
            // fail anyway.
            // nodes can get their share by calling
            // getMyBountySplit anyway.
            c.done = true;
        }
        
        if(c.numValid >= c.numCommits){
            c.done = true;
        }
        emit onReveal(msg.sender, gid, v);
        emit updateStat(gid, c.numCommits, c.numValid);
        return v;
    }
    
    // Get the PRNG generated.
    // Normally this Should be payable to increase bounty pot.
    // TODO
    function prng(uint256 gid) public view returns (uint256){
        ConsensusGroup storage c = rngGroups[gid];
        require(c.numValid>=c.numCommits, "prng group failed");
        require(c.numValid >= c.minParticipants, "Minimum Participants not reached");
        require(c.done, "Campaign is not done");
        return c.random;
    }
    
    function calcSplit(uint256 gid) internal view returns (uint256) {
        ConsensusGroup storage c = rngGroups[gid];
        return c.bountyPot / c.numValid;
    }
    
    function verifySecret(uint256 secret, bytes32 hash) internal pure returns(bool){
        return shaCommit(secret) == hash;
    }
    
    function getMyBountySplit(uint256 gid) public {
        ConsensusGroup storage c = rngGroups[gid];
        require(c.done, "C done");
        Participant storage p= c.participants[msg.sender];
        emit updateStat(gid, c.numCommits, c.numValid);
        // penalize peers which commit and doesn't reveal.
        if(!p.reward && p.committed && p.revealedSecret){
            p.reward = true;
            // Send to the guy
            emit bountySplit(msg.sender, c.bountyPot, calcSplit(gid));
            emit onPay(msg.sender, calcSplit(gid));
            bool success = payable(msg.sender).send(calcSplit(gid));
            require(success, "Unable to send ETH split");
        }
    }
    
    function shaCommit(uint256 _s) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_s));
    }
}