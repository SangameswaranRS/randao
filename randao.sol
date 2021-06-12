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
        // TODO: //
        uint256 phaseTransitionDeadline;
        uint256 minParticipants;
        uint256 bat;
        bool done;
        mapping(address => Participant) participants;
    }
    
    address payable contractOwner;
    uint256 public numSessions;
    ConsensusGroup[1000] rngGroups;
    

    constructor() payable public {
        contractOwner =payable( msg.sender);
        numSessions = 0;
    }
    
    // Creates a new group and returns the group id.
    // adds payable to the bountyPot.
    function newRNGGroup(uint256 ptd, uint256 mp) external payable returns(uint256) {
        //require(msg.value >= 1 ether, "Minimum of 1 ether required to create a RNG campaign");
        ConsensusGroup storage c = rngGroups[numSessions];
        c.phaseTransitionDeadline = ptd;
        c.minParticipants = mp;
        c.bat = block.number;
        c.bountyPot+=msg.value;
        c.numCommits = 0;
        c.numValid = 0;
        c.done = false;
        numSessions++;
        return numSessions-1;
    }
    
    // Commit to a group. Commit phase
    function commitToGroup(uint256 gid, bytes32 hash) public payable returns(bool){
        require(msg.value >= 1 ether, "Minium of 1 ether required to commit to group");
        ConsensusGroup storage c = rngGroups[gid];
        require(!c.done, "C done");
        // Check if its in phaseTransitionDeadline
        require(block.number < (c.bat+ c.phaseTransitionDeadline), "Commit phase expired");
        // Hmm, take the last join to account.
        c.participants[msg.sender] = Participant(msg.sender, 0, hash, true, false, false);
        c.bountyPot += msg.value;
        c.numCommits++;
        return true;
    }
    
    // Reveal secret. Reveal phase
    // TODO: Make sure to start reveal phase only after commit phase.
    function revealPhase(uint256 gid, uint256 secret) public returns(bool) {
        // TODO: Proper state transition is not followed deliberately to manual test.
        ConsensusGroup storage c = rngGroups[gid];
        require(!c.done, "C done");
        require(block.number < (c.bat + 2*c.phaseTransitionDeadline), "Reveal phase done");
        Participant storage p= c.participants[msg.sender];
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
        return v;
    }
    
    // Get the PRNG generated for a GID.
    function prng(uint256 gid) public view returns (uint256){
        ConsensusGroup storage c = rngGroups[gid];
        require(c.numValid>=c.numCommits, "prng group failed");
        require(c.done, "C is not done");
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
        if(!p.reward){
            p.reward = true;
            // Send to the guy
            payable(msg.sender).transfer(calcSplit(gid));
        }
    }
    
    function shaCommit(uint256 _s) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_s));
    }
}