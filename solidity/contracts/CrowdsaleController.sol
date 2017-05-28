pragma solidity ^0.4.11;
import './SmartTokenController.sol';
import './SafeMath.sol';
import './ISmartToken.sol';

/*
    Crowdsale v0.1

    The crowdsale version of the smart token controller, allows buying Bancor with ether
    The price remains fixed for the entire duration of the crowdsale
    Note that 20% of the contributions are the Bancor token's reserve
*/
contract CrowdsaleController is SmartTokenController, SafeMath {
    uint256 public constant DURATION = 14 days;             // crowdsale duration
    uint256 public constant TOKEN_PRICE_N = 1;              // initial price in wei (numerator)
    uint256 public constant TOKEN_PRICE_D = 100;            // initial price in wei (denominator)
    uint256 public constant BTCS_ETHER_CAP = 50000 ether;   // maximum bitcoin suisse ether contribution

    string public version = '0.1';

    uint256 public startTime = 0;                           // crowdsale start time (in seconds)
    uint256 public endTime = 0;                             // crowdsale end time (in seconds)
    uint256 public totalEtherCap = 1000000 ether;           // current ether contribution cap, initialized with a temp value as a safety mechanism until the real cap is revealed
    uint256 public totalEtherContributed = 0;               // ether contributed so far
    bytes32 public realEtherCapHash;                        // ensures that the real cap is predefined on deployment and cannot be changed later
    address public beneficiary = 0x0;                       // address to receive all ether contributions
    address public btcs = 0x0;                              // bitcoin suisse address

    // triggered on each contribution
    event Contribution(address indexed _contributor, uint256 _amount, uint256 _return);

    /**
        @dev constructor

        @param _token          smart token the crowdsale is for
        @param _startTime      crowdsale start time
        @param _beneficiary    address to receive all ether contributions
        @param _btcs           bitcoin suisse address
    */
    function CrowdsaleController(ISmartToken _token, uint256 _startTime, address _beneficiary, address _btcs, bytes32 _realEtherCapHash)
        SmartTokenController(_token)
        validAddress(_beneficiary)
        validAddress(_btcs)
        earlierThan(_startTime)
        validAmount(uint256(_realEtherCapHash))
    {
        startTime = _startTime;
        endTime = startTime + DURATION;
        beneficiary = _beneficiary;
        btcs = _btcs;
        realEtherCapHash = _realEtherCapHash;
    }

    // verifies that the ether cap is valid based on the key provided
    modifier validEtherCap(uint256 _cap, uint256 _key) {
        require(computeRealCap(_cap, _key) == realEtherCapHash);
        _;
    }

    // ensures that it's earlier than the given time
    modifier earlierThan(uint256 _time) {
        assert(now < _time);
        _;
    }

    // ensures that the current time is between _startTime (inclusive) and _endTime (exclusive)
    modifier between(uint256 _startTime, uint256 _endTime) {
        assert(now >= _startTime && now < _endTime);
        _;
    }

    // ensures that the sender is bitcoin suisse
    modifier btcsOnly() {
        assert(msg.sender == btcs);
        _;
    }

    // ensures that we didn't reach the ether cap
    modifier etherCapNotReached(uint256 _contribution) {
        assert(safeAdd(totalEtherContributed, _contribution) <= totalEtherCap);
        _;
    }

    // ensures that we didn't reach the bitcoin suisse ether cap
    modifier btcsEtherCapNotReached(uint256 _ethContribution) {
        assert(safeAdd(totalEtherContributed, _ethContribution) <= BTCS_ETHER_CAP);
        _;
    }

    /**
        @dev enables the real cap defined on deployment

        @param _cap    predefined cap
        @param _key    key used to compute the cap hash
    */
    function enableRealCap(uint256 _cap, uint256 _key)
        public
        ownerOnly
        active
        between(startTime, endTime)
        validAmount(_cap)
        validEtherCap(_cap, _key)
    {
        totalEtherCap = _cap;
    }

    /**
        @dev computes the number of tokens that should be issued for a given contribution

        @param _contribution    contribution amount

        @return computed number of tokens
    */
    function computeReturn(uint256 _contribution) public constant returns (uint256) {
        return safeMul(_contribution, TOKEN_PRICE_D) / TOKEN_PRICE_N;
    }

    /**
        @dev buys the token with ETH
        can only be called during the crowdsale

        @return tokens issued in return
    */
    function buyETH()
        public
        payable
        between(startTime, endTime)
        returns (uint256 amount)
    {
        return processContribution(msg.sender);
    }

    /**
        @dev buys the token with BTCs (Bitcoin Suisse only)
        can only be called before the crowdsale started

        @param _contributor    account that should receive the new tokens

        @return tokens issued in return
    */
    function buyBTCs(address _contributor)
        public
        payable
        validAddress(_contributor)
        btcsOnly
        btcsEtherCapNotReached(msg.value)
        earlierThan(startTime)
        returns (uint256 amount)
    {
        return processContribution(_contributor);
    }

    /**
        @dev handles contribution logic
        note that the Contribution event is triggered using the sender as the contributor, regardless of the actual contributor

        @param _contributor     account that should receive the new tokens

        @return tokens issued in return
    */
    function processContribution(address _contributor) private
        active
        validAmount(msg.value)
        etherCapNotReached(msg.value)
        returns (uint256 amount)
    {
        uint256 tokenAmount = computeReturn(msg.value);
        assert(tokenAmount != 0); // ensure the trade gives something in return

        assert(beneficiary.send(msg.value)); // transfer the ether to the beneficiary account
        totalEtherContributed = safeAdd(totalEtherContributed, msg.value); // update the total contribution amount
        token.issue(_contributor, tokenAmount); // issue new funds to the contributor in the smart token
        token.issue(beneficiary, tokenAmount); // issue tokens to the beneficiary

        Contribution(msg.sender, msg.value, tokenAmount);
        return tokenAmount;
    }

    /**
        @dev computes the real cap based on the given cap & key

        @param _cap    cap
        @param _key    key used to compute the cap hash

        @return computed real cap hash
    */
    function computeRealCap(uint256 _cap, uint256 _key) private returns (bytes32) {
        return sha3(_cap, _key);
    }

    // fallback
    function() payable {
        buyETH();
    }
}
