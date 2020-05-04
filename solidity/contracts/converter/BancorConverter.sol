pragma solidity 0.4.26;
import './interfaces/IBancorConverter.sol';
import './interfaces/IBancorConverterUpgrader.sol';
import './interfaces/IBancorFormula.sol';
import '../IBancorNetwork.sol';
import '../utility/SafeMath.sol';
import '../utility/TokenHandler.sol';
import '../utility/ContractRegistryClient.sol';
import '../token/SmartTokenController.sol';
import '../token/interfaces/ISmartToken.sol';
import '../token/interfaces/IEtherToken.sol';
import '../bancorx/interfaces/IBancorX.sol';

/**
  * @dev Bancor Converter
  * 
  * The Bancor converter allows for conversions between a Smart Token and other ERC20 tokens and between different ERC20 tokens and themselves. 
  * 
  * This mechanism opens the possibility to create different financial tools (for example, lower slippage in conversions).
  * 
  * The converter is upgradable (just like any SmartTokenController) and all upgrades are opt-in. 
*/
contract BancorConverter is IBancorConverter, TokenHandler, SmartTokenController, ContractRegistryClient {
    using SafeMath for uint256;

    uint32 private constant WEIGHT_RESOLUTION = 1000000;
    uint64 private constant CONVERSION_FEE_RESOLUTION = 1000000;
    address private constant ETH_RESERVE_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    struct Reserve {
        uint256 balance;    // reserve balance
        uint32 weight;      // reserve weight, represented in ppm, 1-1000000
        bool deprecated1;   // deprecated
        bool deprecated2;   // deprecated
        bool isSet;         // true if the reserve is valid, false otherwise
    }

    /**
      * @dev version number
    */
    uint16 public version = 28;

    IWhitelist public conversionWhitelist;          // whitelist contract with list of addresses that are allowed to use the converter
    IERC20Token[] public reserveTokens;             // ERC20 standard token addresses (prior version 17, use 'connectorTokens' instead)
    mapping (address => Reserve) public reserves;   // reserve token addresses -> reserve data (prior version 17, use 'connectors' instead)
    uint32 public reserveRatio = 0;                 // ratio between the reserves and the market cap, equal to the total reserve weights
    uint32 public maxConversionFee = 0;             // maximum conversion fee for the lifetime of the contract,
                                                    // represented in ppm, 0...1000000 (0 = no fee, 100 = 0.01%, 1000000 = 100%)
    uint32 public conversionFee = 0;                // current conversion fee, represented in ppm, 0...maxConversionFee
    bool public conversionsEnabled = true;          // deprecated, backward compatibility
    bool private locked = false;                    // true while protected code is being executed, false otherwise

    IEtherToken internal etherToken = IEtherToken(0xc0829421C1d260BD3cB3E0F06cfE2D52db2cE315);

    /**
      * @dev triggered when a conversion between two tokens occurs
      * 
      * @param _fromToken       source ERC20 token
      * @param _toToken         target ERC20 token
      * @param _trader          wallet that initiated the trade
      * @param _amount          amount converted, in the source token
      * @param _return          amount returned, minus conversion fee
      * @param _conversionFee   conversion fee
    */
    event Conversion(
        address indexed _fromToken,
        address indexed _toToken,
        address indexed _trader,
        uint256 _amount,
        uint256 _return,
        int256 _conversionFee
    );

    /**
      * @dev triggered after a conversion with new price data
      * 
      * @param  _connectorToken     reserve token
      * @param  _tokenSupply        smart token supply
      * @param  _connectorBalance   reserve balance
      * @param  _connectorWeight    reserve weight
    */
    event PriceDataUpdate(
        address indexed _connectorToken,
        uint256 _tokenSupply,
        uint256 _connectorBalance,
        uint32 _connectorWeight
    );

    /**
      * @dev triggered after liquidity is added
      * 
      * @param  _provider   liquidity provider
      * @param  _reserve    reserve token address
      * @param  _amount     reserve token amount
      * @param  _newBalance reserve token new balance
      * @param  _newSupply  smart token new supply
    */
    event LiquidityAdded(
        address indexed _provider,
        address indexed _reserve,
        uint256 _amount,
        uint256 _newBalance,
        uint256 _newSupply
    );

    /**
      * @dev triggered after liquidity is removed
      * 
      * @param  _provider   liquidity provider
      * @param  _reserve    reserve token address
      * @param  _amount     reserve token amount
      * @param  _newBalance reserve token new balance
      * @param  _newSupply  smart token new supply
    */
    event LiquidityRemoved(
        address indexed _provider,
        address indexed _reserve,
        uint256 _amount,
        uint256 _newBalance,
        uint256 _newSupply
    );

    /**
      * @dev triggered when the conversion fee is updated
      * 
      * @param  _prevFee    previous fee percentage, represented in ppm
      * @param  _newFee     new fee percentage, represented in ppm
    */
    event ConversionFeeUpdate(uint32 _prevFee, uint32 _newFee);

    /**
      * @dev initializes a new BancorConverter instance
      * 
      * @param  _token              smart token governed by the converter
      * @param  _registry           address of a contract registry contract
      * @param  _maxConversionFee   maximum conversion fee, represented in ppm
      * @param  _reserveToken       optional, initial reserve, allows defining the first reserve at deployment time
      * @param  _reserveWeight      optional, weight for the initial reserve
    */
    constructor(
        ISmartToken _token,
        IContractRegistry _registry,
        uint32 _maxConversionFee,
        IERC20Token _reserveToken,
        uint32 _reserveWeight
    )
        SmartTokenController(_token)
        ContractRegistryClient(_registry)
        public
        validConversionFee(_maxConversionFee)
    {
        maxConversionFee = _maxConversionFee;

        if (_reserveToken != address(0))
            addReserve(_reserveToken, _reserveWeight);
    }

    // protects a function against reentrancy attacks
    modifier protected() {
        require(!locked);
        locked = true;
        _;
        locked = false;
    }

    // validates a reserve token address - verifies that the address belongs to one of the reserve tokens
    modifier validReserve(IERC20Token _address) {
        require(reserves[_address].isSet);
        _;
    }

    // validates conversion fee
    modifier validConversionFee(uint32 _conversionFee) {
        require(_conversionFee >= 0 && _conversionFee <= CONVERSION_FEE_RESOLUTION);
        _;
    }

    // validates reserve weight
    modifier validReserveWeight(uint32 _weight) {
        require(_weight > 0 && _weight <= WEIGHT_RESOLUTION);
        _;
    }

    // allows execution only on a multiple-reserve converter
    modifier multipleReservesOnly {
        require(reserveTokens.length > 1);
        _;
    }

    /**
      * @dev deposit ether
      * can only be called if the converter has an ETH reserve
    */
    function() external payable {
        require(reserves[ETH_RESERVE_ADDRESS].isSet); // require(hasETHReserve());
        // a workaround for a problem when running solidity-coverage
        // see https://github.com/sc-forks/solidity-coverage/issues/487
    }

    /**
      * @dev withdraw ether
      * can only be called by the upgrader contract
      * can only be called after the upgrader contract has accepted the ownership of this contract
      * can only be called if the converter has an ETH reserve
    */
    function withdrawETH(address _to) public ownerOnly only(BANCOR_CONVERTER_UPGRADER) {
        require(hasETHReserve());
        _to.transfer(address(this).balance);

        // sync the ETH reserve balance	
        syncReserveBalance(IERC20Token(ETH_RESERVE_ADDRESS));
    }

    /**
      * @dev checks whether or not the converter version is 28 or higher
      * 
      * @return true, since the converter version is 28 or higher
    */
    function isV28OrHigher() public pure returns (bool) {
        return true;
    }

    /**
      * @dev returns the number of reserve tokens defined
      * note that prior to version 17, you should use 'connectorTokenCount' instead
      * 
      * @return number of reserve tokens
    */
    function reserveTokenCount() public view returns (uint16) {
        return uint16(reserveTokens.length);
    }

    /**
      * @dev allows the owner to update & enable the conversion whitelist contract address
      * when set, only addresses that are whitelisted are actually allowed to use the converter
      * note that the whitelist check is actually done by the BancorNetwork contract
      * 
      * @param _whitelist    address of a whitelist contract
    */
    function setConversionWhitelist(IWhitelist _whitelist)
        public
        ownerOnly
        notThis(_whitelist)
    {
        conversionWhitelist = _whitelist;
    }

    /**
      * @dev allows transferring the token ownership
      * the new owner needs to accept the transfer
      * can only be called by the contract owner
      * note that token ownership can only be transferred while the owner is the converter upgrader contract
      * 
      * @param _newOwner    new token owner
    */
    function transferTokenOwnership(address _newOwner)
        public
        ownerOnly
        only(BANCOR_CONVERTER_UPGRADER)
    {
        super.transferTokenOwnership(_newOwner);
    }

    /**
      * @dev used by a new owner to accept a token ownership transfer
      * can only be called by the contract owner
      * note that token ownership can only be accepted if its total-supply is greater than zero
    */
    function acceptTokenOwnership()
        public
        ownerOnly
    {
        super.acceptTokenOwnership();
        syncReserveBalances();
    }

    /**
      * @dev updates the current conversion fee
      * can only be called by the contract owner
      * 
      * @param _conversionFee new conversion fee, represented in ppm
    */
    function setConversionFee(uint32 _conversionFee)
        public
        ownerOnly
    {
        require(_conversionFee >= 0 && _conversionFee <= maxConversionFee);
        emit ConversionFeeUpdate(conversionFee, _conversionFee);
        conversionFee = _conversionFee;
    }

    /**
      * @dev given a return amount, returns the amount minus the conversion fee
      * 
      * @param _amount      return amount
      * @param _magnitude   1 for standard conversion, 2 for cross reserve conversion
      * 
      * @return return amount minus conversion fee
    */
    function getFinalAmount(uint256 _amount, uint8 _magnitude) public view returns (uint256) {
        return _amount.mul((CONVERSION_FEE_RESOLUTION - conversionFee) ** _magnitude).div(CONVERSION_FEE_RESOLUTION ** _magnitude);
    }

    /**
      * @dev withdraws tokens held by the converter and sends them to an account
      * can only be called by the owner
      * note that reserve tokens can only be withdrawn by the owner while the converter is inactive
      * unless the owner is the converter upgrader contract
      * 
      * @param _token   ERC20 token contract address
      * @param _to      account to receive the new amount
      * @param _amount  amount to withdraw
    */
    function withdrawTokens(IERC20Token _token, address _to, uint256 _amount) public {
        address converterUpgrader = addressOf(BANCOR_CONVERTER_UPGRADER);

        // if the token is not a reserve token, allow withdrawal
        // otherwise verify that the converter is inactive or that the owner is the upgrader contract
        require(!reserves[_token].isSet || token.owner() != address(this) || owner == converterUpgrader);
        super.withdrawTokens(_token, _to, _amount);

        // if the token is a reserve token, sync the reserve balance
        if (reserves[_token].isSet)
            syncReserveBalance(_token);
    }

    /**
      * @dev upgrades the converter to the latest version
      * can only be called by the owner
      * note that the owner needs to call acceptOwnership on the new converter after the upgrade
    */
    function upgrade() public ownerOnly {
        IBancorConverterUpgrader converterUpgrader = IBancorConverterUpgrader(addressOf(BANCOR_CONVERTER_UPGRADER));

        transferOwnership(converterUpgrader);
        converterUpgrader.upgrade(version);
        acceptOwnership();
    }

    /**
      * @dev defines a new reserve token for the converter
      * can only be called by the owner while the converter is inactive
      * note that prior to version 17, you should use 'addConnector' instead
      * 
      * @param _token   address of the reserve token
      * @param _weight  reserve weight, represented in ppm, 1-1000000
    */
    function addReserve(IERC20Token _token, uint32 _weight)
        public
        ownerOnly
        inactive
        validAddress(_token)
        notThis(_token)
        validReserveWeight(_weight)
    {
        require(_token != token && !reserves[_token].isSet && reserveRatio + _weight <= WEIGHT_RESOLUTION); // validate input

        reserves[_token].balance = 0;
        reserves[_token].weight = _weight;
        reserves[_token].isSet = true;
        reserveTokens.push(_token);
        reserveRatio += _weight;
    }

    /**
      * @dev checks whether or not the converter has an ETH reserve
      * 
      * @return true if the converter has an ETH reserve, false otherwise
    */
    function hasETHReserve() public view returns (bool) {
        return reserves[ETH_RESERVE_ADDRESS].isSet;
    }

    /**
      * @dev returns the reserve's weight
      * added in version 28
      * 
      * @param _reserveToken    reserve token contract address
      * 
      * @return reserve weight
    */
    function reserveWeight(IERC20Token _reserveToken)
        public
        view
        validReserve(_reserveToken)
        returns (uint256)
    {
        return reserves[_reserveToken].weight;
    }

    /**
      * @dev returns the reserve's balance
      * note that prior to version 17, you should use 'getConnectorBalance' instead
      * 
      * @param _reserveToken    reserve token contract address
      * 
      * @return reserve balance
    */
    function reserveBalance(IERC20Token _reserveToken)
        public
        view
        validReserve(_reserveToken)
        returns (uint256)
    {
        return reserves[_reserveToken].balance;
    }

    /**
      * @dev calculates the expected return of converting a given amount of tokens
      * 
      * @param _sourceToken contract address of the source token
      * @param _targetToken contract address of the target token
      * @param _amount     amount of tokens received from the user
      * 
      * @return amount of tokens that the user will receive
      * @return amount of tokens that the user will pay as fee
    */
    function getReturn(IERC20Token _sourceToken, IERC20Token _targetToken, uint256 _amount) public view returns (uint256, uint256) {
        require(_sourceToken != _targetToken); // validate input

        if (_targetToken == token)
            return getPurchaseReturn(_sourceToken, _amount);
        else if (_sourceToken == token)
            return getSaleReturn(_targetToken, _amount);
        else
            return getCrossReserveReturn(_sourceToken, _targetToken, _amount);
    }

    /**
      * @dev calculates the expected return of buying with a given amount of tokens
      * 
      * @param _reserveToken    contract address of the reserve token
      * @param _depositAmount   amount of reserve-tokens received from the user
      * 
      * @return amount of supply-tokens that the user will receive
      * @return amount of supply-tokens that the user will pay as fee
    */
    function getPurchaseReturn(IERC20Token _reserveToken, uint256 _depositAmount)
        internal
        view
        active
        validReserve(_reserveToken)
        returns (uint256, uint256)
    {
        uint256 amount = IBancorFormula(addressOf(BANCOR_FORMULA)).calculatePurchaseReturn(
            token.totalSupply(),
            reserveBalance(_reserveToken),
            reserves[_reserveToken].weight,
            _depositAmount
        );

        uint256 finalAmount = getFinalAmount(amount, 1);

        // return the amount minus the conversion fee and the conversion fee
        return (finalAmount, amount - finalAmount);
    }

    /**
      * @dev calculates the expected return of selling a given amount of tokens
      * 
      * @param _reserveToken    contract address of the reserve token
      * @param _sellAmount      amount of supply-tokens received from the user
      * 
      * @return amount of reserve-tokens that the user will receive
      * @return amount of reserve-tokens that the user will pay as fee
    */
    function getSaleReturn(IERC20Token _reserveToken, uint256 _sellAmount)
        internal
        view
        active
        validReserve(_reserveToken)
        returns (uint256, uint256)
    {
        uint256 amount = IBancorFormula(addressOf(BANCOR_FORMULA)).calculateSaleReturn(
            token.totalSupply(),
            reserveBalance(_reserveToken),
            reserves[_reserveToken].weight,
            _sellAmount
        );

        uint256 finalAmount = getFinalAmount(amount, 1);

        // return the amount minus the conversion fee and the conversion fee
        return (finalAmount, amount - finalAmount);
    }

    /**
      * @dev calculates the expected return of converting a given amount from one reserve to another
      * 
      * @param _fromReserveToken    contract address of the reserve token to convert from
      * @param _toReserveToken      contract address of the reserve token to convert to
      * @param _amount              amount of tokens received from the user
      * 
      * @return amount of tokens that the user will receive
      * @return amount of tokens that the user will pay as fee
    */
    function getCrossReserveReturn(IERC20Token _fromReserveToken, IERC20Token _toReserveToken, uint256 _amount)
        internal
        view
        active
        validReserve(_fromReserveToken)
        validReserve(_toReserveToken)
        returns (uint256, uint256)
    {
        uint256 amount = IBancorFormula(addressOf(BANCOR_FORMULA)).calculateCrossReserveReturn(
            reserveBalance(_fromReserveToken),
            reserves[_fromReserveToken].weight,
            reserveBalance(_toReserveToken),
            reserves[_toReserveToken].weight,
            _amount
        );

        // using a magnitude of 2 because this operation is equivalent to 2 conversions (to/from the smart token)
        uint256 finalAmount = getFinalAmount(amount, 2);

        // return the amount minus the conversion fee and the conversion fee
        return (finalAmount, amount - finalAmount);
    }

    /**
      * @dev converts a specific amount of _sourceToken to _targetToken
      * can only be called by the bancor network contract
      *
      * @param _sourceToken source ERC20 token
      * @param _targetToken target ERC20 token
      * @param _amount      amount of tokens to convert (in units of the source token)
      * @param _beneficiary wallet to receive the conversion result
      *
      * @return amount of tokens received (in units of the target token)
    */
    function convert(IERC20Token _sourceToken, IERC20Token _targetToken, uint256 _amount, address _trader, address _beneficiary)
        public
        payable
        protected
        only(BANCOR_NETWORK)
        returns (uint256)
    {
        require(_sourceToken != _targetToken); // validate input

        // if a whitelist is set, verify that both and trader and the beneficiary are whitelisted
        require(conversionWhitelist == address(0) ||
                (conversionWhitelist.isWhitelisted(_trader) && conversionWhitelist.isWhitelisted(_beneficiary)));

        if (_targetToken == token)
            return buy(_sourceToken, _amount, _beneficiary);
        else if (_sourceToken == token)
            return sell(_targetToken, _amount, _beneficiary);
        else
            return crossConvert(_sourceToken, _targetToken, _amount, _beneficiary);
    }

    /**
      * @dev buys the smart token by depositing one of its reserve tokens
      * 
      * @param _reserveToken    reserve token contract address
      * @param _depositAmount   amount of tokens to deposit (in units of the reserve token)
      * @param _beneficiary     wallet to receive the conversion result
      * 
      * @return amount of tokens received (in units of the smart token)
    */
    function buy(IERC20Token _reserveToken, uint256 _depositAmount, address _beneficiary) internal returns (uint256) {
        (uint256 amount, uint256 feeAmount) = getPurchaseReturn(_reserveToken, _depositAmount);

        // ensure the trade gives something in return
        require(amount != 0);

        // ensure that the input amount was already deposited
        if (_reserveToken == ETH_RESERVE_ADDRESS)
            require(msg.value == _depositAmount);
        else
            require(msg.value == 0 && _reserveToken.balanceOf(this).sub(reserveBalance(_reserveToken)) >= _depositAmount);

        // sync the reserve balance
        syncReserveBalance(_reserveToken);

        // issue new funds to the beneficiary in the smart token
        token.issue(_beneficiary, amount);

        // dispatch the conversion event
        dispatchConversionEvent(_reserveToken, token, _depositAmount, amount, feeAmount);

        // dispatch price data update for the smart token/reserve
        emit PriceDataUpdate(_reserveToken, token.totalSupply(), reserveBalance(_reserveToken), reserves[_reserveToken].weight);

        return amount;
    }

    /**
      * @dev sells the smart token by withdrawing from one of its reserve tokens
      * 
      * @param _reserveToken    reserve token contract address
      * @param _sellAmount      amount of tokens to sell (in units of the smart token)
      * @param _beneficiary     wallet to receive the conversion result
      * 
      * @return amount of tokens received (in units of the reserve token)
    */
    function sell(IERC20Token _reserveToken, uint256 _sellAmount, address _beneficiary) internal returns (uint256) {
        // ensure that the input amount was already deposited
        require(_sellAmount <= token.balanceOf(this));

        (uint256 amount, uint256 feeAmount) = getSaleReturn(_reserveToken, _sellAmount);

        // ensure the trade gives something in return
        require(amount != 0);

        // ensure that the trade will only deplete the reserve balance if the total supply is depleted as well
        uint256 tokenSupply = token.totalSupply();
        uint256 rsvBalance = reserveBalance(_reserveToken);
        assert(amount < rsvBalance || (amount == rsvBalance && _sellAmount == tokenSupply));

        // destroy _sellAmount from the converter balance in the smart token
        token.destroy(this, _sellAmount);

        // update the reserve balance
        reserves[_reserveToken].balance = reserves[_reserveToken].balance.sub(amount);

        // transfer funds to the beneficiary in the reserve token
        if (_reserveToken == ETH_RESERVE_ADDRESS)
            _beneficiary.transfer(amount);
        else
            safeTransfer(_reserveToken, _beneficiary, amount);

        // dispatch the conversion event
        dispatchConversionEvent(token, _reserveToken, _sellAmount, amount, feeAmount);

        // dispatch price data update for the smart token/reserve
        emit PriceDataUpdate(_reserveToken, token.totalSupply(), reserveBalance(_reserveToken), reserves[_reserveToken].weight);

        return amount;
    }

    /**
      * @dev converts one of the reserve tokens to the other
      * 
      * @param _sourceToken source reserve token contract address
      * @param _targetToken target reserve token contract address
      * @param _amount      amount of tokens to convert (in units of the source reserve token)
      * @param _beneficiary wallet to receive the conversion result
      * 
      * @return amount of tokens received (in units of the target reserve token)
    */
    function crossConvert(IERC20Token _sourceToken, IERC20Token _targetToken, uint256 _amount, address _beneficiary) internal returns (uint256) {
        (uint256 amount, uint256 feeAmount) = getCrossReserveReturn(_sourceToken, _targetToken, _amount);

        // ensure the trade gives something in return
        require(amount != 0);

        // ensure that the trade won't deplete the reserve balance
        uint256 toReserveBalance = reserveBalance(_targetToken);
        assert(amount < toReserveBalance);

        // ensure that the input amount was already deposited
        if (_sourceToken == ETH_RESERVE_ADDRESS)
            require(msg.value == _amount);
        else
            require(msg.value == 0 && _sourceToken.balanceOf(this).sub(reserveBalance(_sourceToken)) >= _amount);

        // sync the reserve balances
        syncReserveBalance(_sourceToken);
        reserves[_targetToken].balance = reserves[_targetToken].balance.sub(amount);

        // transfer funds to the beneficiary in the to reserve token
        if (_targetToken == ETH_RESERVE_ADDRESS)
            _beneficiary.transfer(amount);
        else
            safeTransfer(_targetToken, _beneficiary, amount);

        // dispatch the conversion event
        dispatchConversionEvent(_sourceToken, _targetToken, _amount, amount, feeAmount);

        // dispatch price data updates for the smart token / both reserves
        emit PriceDataUpdate(_sourceToken, token.totalSupply(), reserveBalance(_sourceToken), reserves[_sourceToken].weight);
        emit PriceDataUpdate(_targetToken, token.totalSupply(), reserveBalance(_targetToken), reserves[_targetToken].weight);

        return amount;
    }

    /**
      * @dev allows a user to convert BNT that was sent from another blockchain into any other
      * token on the BancorNetwork without specifying the amount of BNT to be converted, but
      * rather by providing the xTransferId which allows us to get the amount from BancorX.
      * note that prior to version 16, you should use 'completeXConversion' instead
      * 
      * @param _path            conversion path, see conversion path format in the BancorNetwork contract
      * @param _minReturn       if the conversion results in an amount smaller than the minimum return - it is cancelled, must be nonzero
      * @param _conversionId    pre-determined unique (if non zero) id which refers to this transaction 
      * 
      * @return tokens issued in return
    */
    function completeXConversion2(
        IERC20Token[] _path,
        uint256 _minReturn,
        uint256 _conversionId
    )
        public
        returns (uint256)
    {
        IBancorX bancorX = IBancorX(addressOf(BANCOR_X));
        IBancorNetwork bancorNetwork = IBancorNetwork(addressOf(BANCOR_NETWORK));

        // verify that the first token in the path is BNT
        require(_path[0] == addressOf(BNT_TOKEN));

        // get conversion amount from BancorX contract
        uint256 amount = bancorX.getXTransferAmount(_conversionId, msg.sender);

        // send BNT from msg.sender to the converter contract
        token.destroy(msg.sender, amount);
        token.issue(this, amount);

        // grant allowance to the network
        uint256 allowance = token.allowance(this, bancorNetwork);
        if (allowance < amount) {
            if (allowance > 0)
                safeApprove(token, bancorNetwork, 0);
            safeApprove(token, bancorNetwork, amount);
        }

        return bancorNetwork.claimAndConvertFor2(_path, amount, _minReturn, msg.sender, address(0), 0);
    }

    /**
      * @dev buys the token with all reserve tokens using the same percentage
      * for example, if the caller increases the supply by 10%,
      * then it will cost an amount equal to 10% of each reserve token balance
      * note that the function cannot be called when the converter has only one reserve
      * 
      * @param _amount  amount to increase the supply by (in the smart token)
    */
    function fund(uint256 _amount)
        public
        payable
        protected
        multipleReservesOnly
    {
        uint256 supply = token.totalSupply();
        IBancorFormula formula = IBancorFormula(addressOf(BANCOR_FORMULA));

        // iterate through the reserve tokens and transfer a percentage equal to the weight between
        // _amount and the total supply in each reserve from the caller to the converter
        for (uint256 i = 0; i < reserveTokens.length; i++) {
            IERC20Token reserveToken = reserveTokens[i];
            uint256 rsvBalance = reserveBalance(reserveToken);
            uint256 reserveAmount = formula.calculateFundCost(supply, rsvBalance, reserveRatio, _amount);

            // transfer funds from the caller in the reserve token
            if (reserveToken == ETH_RESERVE_ADDRESS) {
                if (msg.value > reserveAmount) {
                    msg.sender.transfer(msg.value - reserveAmount);
                }
                else if (msg.value < reserveAmount) {
                    require(msg.value == 0);
                    safeTransferFrom(etherToken, msg.sender, this, reserveAmount);
                    etherToken.withdraw(reserveAmount);
                }
            }
            else {
                safeTransferFrom(reserveToken, msg.sender, this, reserveAmount);
            }

            // sync the reserve balance
            syncReserveBalance(reserveToken);

            // dispatch liquidity update for the smart token/reserve
            emit LiquidityAdded(msg.sender, reserveToken, reserveAmount, rsvBalance + reserveAmount, supply + _amount);
        }

        // issue new funds to the caller in the smart token
        token.issue(msg.sender, _amount);
    }

    /**
      * @dev sells the token for all reserve tokens using the same percentage
      * for example, if the holder sells 10% of the supply,
      * then they will receive 10% of each reserve token balance in return
      * note that the function cannot be called when the converter has only one reserve
      * 
      * @param _amount  amount to liquidate (in the smart token)
    */
    function liquidate(uint256 _amount)
        public
        protected
        multipleReservesOnly
    {
        uint256 supply = token.totalSupply();
        IBancorFormula formula = IBancorFormula(addressOf(BANCOR_FORMULA));

        // destroy _amount from the caller's balance in the smart token
        token.destroy(msg.sender, _amount);

        // iterate through the reserve tokens and send a percentage equal to the weight between
        // _amount and the total supply from each reserve balance to the caller
        for (uint256 i = 0; i < reserveTokens.length; i++) {
            IERC20Token reserveToken = reserveTokens[i];
            uint256 rsvBalance = reserveBalance(reserveToken);
            uint256 reserveAmount = formula.calculateLiquidateReturn(supply, rsvBalance, reserveRatio, _amount);

            reserves[reserveToken].balance = reserves[reserveToken].balance.sub(reserveAmount);

            // transfer funds to the caller in the reserve token
            if (reserveToken == ETH_RESERVE_ADDRESS)
                msg.sender.transfer(reserveAmount);
            else
                safeTransfer(reserveToken, msg.sender, reserveAmount);

            // dispatch liquidity update for the smart token/reserve
            emit LiquidityRemoved(msg.sender, reserveToken, reserveAmount, rsvBalance - reserveAmount, supply - _amount);
        }
    }

    /**
      * @dev buys the token with all reserve tokens using the same percentage
      * note that the function cannot be called when the converter has only one reserve
      * 
      * @param _reserveTokens           address of each reserve token
      * @param _reserveAmounts          amount of each reserve token
      * @param _supplyMinReturnAmount   token minimum return-amount
    */
    function addLiquidity(IERC20Token[] memory _reserveTokens, uint256[] memory _reserveAmounts, uint256 _supplyMinReturnAmount)
        public
        payable
        protected
        multipleReservesOnly
    {
        verifyLiquidityInput(_reserveTokens, _reserveAmounts, _supplyMinReturnAmount);

        for (uint256 i = 0; i < _reserveTokens.length; i++)
            if (_reserveTokens[i] == ETH_RESERVE_ADDRESS)
                require(_reserveAmounts[i] == msg.value);

        if (msg.value > 0)
            require(reserves[ETH_RESERVE_ADDRESS].isSet);

        uint256 totalSupply = token.totalSupply();
        uint256 supplyAmount = addLiquidityToPool(_reserveTokens, _reserveAmounts, totalSupply);

        require(supplyAmount >= _supplyMinReturnAmount);
        token.issue(msg.sender, supplyAmount);
    }

    /**
      * @dev sells the token for all reserve tokens using the same percentage
      * note that the function cannot be called when the converter has only one reserve
      * 
      * @param _reserveTokens           address of each reserve token
      * @param _reserveMinReturnAmounts minimum return-amount of each reserve token
      * @param _supplyAmount            token amount
    */
    function removeLiquidity(IERC20Token[] memory _reserveTokens, uint256[] memory _reserveMinReturnAmounts, uint256 _supplyAmount)
        public
        protected
        multipleReservesOnly
    {
        verifyLiquidityInput(_reserveTokens, _reserveMinReturnAmounts, _supplyAmount);

        uint256 totalSupply = token.totalSupply();
        token.destroy(msg.sender, _supplyAmount);

        removeLiquidityFromPool(_reserveTokens, _reserveMinReturnAmounts, totalSupply, _supplyAmount);
    }

    function verifyLiquidityInput(IERC20Token[] memory _reserveTokens, uint256[] memory _reserveAmounts, uint256 _supplyAmount)
        private
        view
    {
        uint256 i;
        uint256 j;

        uint256 length = reserveTokens.length;
        require(length == _reserveTokens.length);
        require(length == _reserveAmounts.length);

        for (i = 0; i < length; i++) {
            require(reserves[_reserveTokens[i]].isSet);
            for (j = 0; j < length; j++) {
                if (reserveTokens[i] == _reserveTokens[j])
                    break;
            }
            require(j < length);
            require(_reserveAmounts[i] > 0);
        }

        require(_supplyAmount > 0);
    }

    function addLiquidityToPool(IERC20Token[] memory _reserveTokens, uint256[] memory _reserveAmounts, uint256 _totalSupply)
        private
        returns (uint256)
    {
        if (_totalSupply == 0)
            return addLiquidityToEmptyPool(_reserveTokens, _reserveAmounts);
        return addLiquidityToNonEmptyPool(_reserveTokens, _reserveAmounts, _totalSupply);
    }

    function addLiquidityToEmptyPool(IERC20Token[] memory _reserveTokens, uint256[] memory _reserveAmounts)
        private
        returns (uint256)
    {
        uint256 supplyAmount = geometricMean(_reserveAmounts);

        for (uint256 i = 0; i < _reserveTokens.length; i++) {
            if (_reserveTokens[i] != ETH_RESERVE_ADDRESS)
                safeTransferFrom(_reserveTokens[i], msg.sender, this, _reserveAmounts[i]);
            emit LiquidityAdded(msg.sender, _reserveTokens[i], _reserveAmounts[i], _reserveAmounts[i], supplyAmount);
        }

        return supplyAmount;
    }

    function addLiquidityToNonEmptyPool(IERC20Token[] memory _reserveTokens, uint256[] memory _reserveAmounts, uint256 _totalSupply)
        private
        returns (uint256)
    {
        uint256[] memory reserveBalances = getBalances(_reserveTokens);
        IBancorFormula formula = IBancorFormula(addressOf(BANCOR_FORMULA));
        uint256 supplyAmount = getMinShare(_totalSupply, reserveBalances, _reserveAmounts);

        for (uint256 i = 0; i < _reserveTokens.length; i++) {
            uint256 reserveAmount = formula.calculateFundCost(_totalSupply, reserveBalances[i], reserveRatio, supplyAmount);
            require(reserveAmount > 0);
            assert(reserveAmount <= _reserveAmounts[i]);

            if (_reserveTokens[i] != ETH_RESERVE_ADDRESS)
                safeTransferFrom(_reserveTokens[i], msg.sender, this, reserveAmount);
            else if (_reserveAmounts[i] > reserveAmount)
                msg.sender.transfer(_reserveAmounts[i] - reserveAmount);

            emit LiquidityAdded(msg.sender, _reserveTokens[i], reserveAmount, reserveBalances[i] + reserveAmount, _totalSupply + supplyAmount);
        }

        return supplyAmount;
    }

    function removeLiquidityFromPool(IERC20Token[] memory _reserveTokens, uint256[] memory _reserveMinReturnAmounts, uint256 _totalSupply, uint256 _supplyAmount)
        public
        multipleReservesOnly
    {
        uint256[] memory reserveBalances = getBalances(_reserveTokens);
        IBancorFormula formula = IBancorFormula(addressOf(BANCOR_FORMULA));

        for (uint256 i = 0; i < _reserveTokens.length; i++) {
            uint256 reserveAmount = formula.calculateLiquidateReturn(_totalSupply, reserveBalances[i], reserveRatio, _supplyAmount);
            require(reserveAmount >= _reserveMinReturnAmounts[i]);

            if (_reserveTokens[i] == ETH_RESERVE_ADDRESS)
                msg.sender.transfer(reserveAmount);
            else
                safeTransfer(_reserveTokens[i], msg.sender, reserveAmount);

            emit LiquidityRemoved(msg.sender, _reserveTokens[i], reserveAmount, reserveBalances[i] - reserveAmount, _totalSupply - _supplyAmount);
        }
    }

    function getBalances(IERC20Token[] memory _tokens) private view returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](_tokens.length);
        for (uint256 i = 0; i < _tokens.length; i++) {
            if (_tokens[i] != ETH_RESERVE_ADDRESS)
                balances[i] = _tokens[i].balanceOf(this);
            else
                balances[i] = address(this).balance - msg.value;
        }
        return balances;
    }

    function getMinShare(uint256 _supply, uint256[] memory _balances, uint256[] memory _amounts) private view returns (uint256) {
        uint256 minShare = getShare(_supply, _balances[0], _amounts[0]);
        for (uint256 i = 1; i < _balances.length; i++) {
            uint256 share = getShare(_supply, _balances[i], _amounts[i]);
            if (minShare > share)
                minShare = share;
        }
        return minShare;
    }

    function getShare(uint256 _supply, uint256 _balance, uint256 _amount) private view returns (uint256) {
        return _supply.mul(_amount).mul(reserveRatio).div(_balance.add(_amount).mul(WEIGHT_RESOLUTION));
    }

    function ceilLog(uint256 _x) public pure returns (uint256) {
        uint256 y = 0;
        while (_x > 0) {
            _x /= 10;
            y += 1;
        }
        return y;
    }

    function roundDiv(uint256 _n, uint256 _d) public pure returns (uint256) {
        return (_n + _d / 2) / _d;
    }

    function geometricMean(uint256[] memory _values) public pure returns (uint256) {
        uint256 numOfDigits = 0;
        uint256 length = _values.length;
        for (uint256 i = 0; i < length; i++)
            numOfDigits += ceilLog(_values[i]);
        return uint256(10) ** (roundDiv(numOfDigits, length) - 1);
    }

    /**	
      * @dev syncs the stored reserve balance for a given reserve with the real reserve balance
      *
      * @param _reserveToken    address of the reserve token
    */
    function syncReserveBalance(IERC20Token _reserveToken) internal validReserve(_reserveToken) {
        if (_reserveToken == ETH_RESERVE_ADDRESS)
            reserves[_reserveToken].balance = address(this).balance;
        else
            reserves[_reserveToken].balance = _reserveToken.balanceOf(this);
    }

    /**	
      * @dev syncs all stored reserve balances
    */
    function syncReserveBalances() internal {
        for (uint256 i = 0; i < reserveTokens.length; i++)
            syncReserveBalance(reserveTokens[i]);
    }

    /**
      * @dev helper, dispatches the Conversion event
      * 
      * @param _sourceToken     source ERC20 token
      * @param _targetToken     target ERC20 token
      * @param _amount          amount purchased/sold (in the source token)
      * @param _returnAmount    amount returned (in the target token)
    */
    function dispatchConversionEvent(IERC20Token _sourceToken, IERC20Token _targetToken, uint256 _amount, uint256 _returnAmount, uint256 _feeAmount) private {
        // fee amount is converted to 255 bits -
        // negative amount means the fee is taken from the source token, positive amount means its taken from the target token
        // currently the fee is always taken from the target token
        // since we convert it to a signed number, we first ensure that it's capped at 255 bits to prevent overflow
        assert(_feeAmount < 2 ** 255);
        emit Conversion(_sourceToken, _targetToken, msg.sender, _amount, _returnAmount, int256(_feeAmount));
    }

    /**
      * @dev deprecated, backward compatibility
    */
    function completeXConversion(IERC20Token[] _path, uint256 _minReturn, uint256 _conversionId, uint256, uint8, bytes32, bytes32) public returns (uint256) {
        return completeXConversion2(_path, _minReturn, _conversionId);
    }

    /**
      * @dev deprecated, backward compatibility
    */
    function connectors(address _address) public view returns (uint256, uint32, bool, bool, bool) {
        Reserve storage reserve = reserves[_address];
        return(reserve.balance, reserve.weight, false, false, reserve.isSet);
    }

    /**
      * @dev deprecated, backward compatibility
    */
    function connectorTokens(uint256 _index) public view returns (IERC20Token) {
        return BancorConverter.reserveTokens[_index];
    }

    /**
      * @dev deprecated, backward compatibility
    */
    function connectorTokenCount() public view returns (uint16) {
        return reserveTokenCount();
    }

    /**
      * @dev deprecated, backward compatibility
    */
    function addConnector(IERC20Token _token, uint32 _weight, bool /*_enableVirtualBalance*/) public {
        addReserve(_token, _weight);
    }

    /**
      * @dev deprecated, backward compatibility
    */
    function getConnectorBalance(IERC20Token _connectorToken) public view returns (uint256) {
        return reserveBalance(_connectorToken);
    }
}
