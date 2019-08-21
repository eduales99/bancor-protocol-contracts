pragma solidity ^0.4.24;
import './interfaces/IBancorConverter.sol';
import './interfaces/IBancorConverterUpgrader.sol';
import './interfaces/IBancorFormula.sol';
import '../IBancorNetwork.sol';
import '../ContractIds.sol';
import '../FeatureIds.sol';
import '../utility/Managed.sol';
import '../utility/Utils.sol';
import '../utility/SafeMath.sol';
import '../utility/interfaces/IContractRegistry.sol';
import '../utility/interfaces/IContractFeatures.sol';
import '../utility/interfaces/IAddressList.sol';
import '../token/SmartTokenController.sol';
import '../token/interfaces/ISmartToken.sol';
import '../token/interfaces/INonStandardERC20.sol';
import '../token/interfaces/IEtherToken.sol';
import '../bancorx/interfaces/IBancorX.sol';

/**
    @dev Bancor Converter

    The Bancor converter allows for conversions between a Smart Token and other ERC20 tokens and between different ERC20 tokens and themselves. 

    The ERC20 connector balance can be virtual, meaning that the calculations are based on the virtual balance instead of relying on the actual connector balance.

    This is a security mechanism that prevents the need to keep a very large (and valuable) balance in a single contract. 

    The converter is upgradable (just like any SmartTokenController) and all upgrades are opt-in. 

    WARNING: It is NOT RECOMMENDED to use the converter with Smart Tokens that have less than 8 decimal digits or with very small numbers because of precision loss 

    Open issues:
    - Front-running attacks are currently mitigated by the following mechanisms:
        - minimum return argument for each conversion provides a way to define a minimum/maximum price for the transaction
        - gas price limit prevents users from having control over the order of execution
        - gas price limit check can be skipped if the transaction comes from a trusted, whitelisted signer

    Other potential solutions might include a commit/reveal based schemes
    - Possibly add getters for the connector fields so that the client won't need to rely on the order in the struct
*/
contract BancorConverter is IBancorConverter, SmartTokenController, Managed, ContractIds, FeatureIds {
    using SafeMath for uint256;

    
    uint32 private constant MAX_WEIGHT = 1000000;
    uint64 private constant MAX_CONVERSION_FEE = 1000000;

    struct Connector {
        uint256 virtualBalance;         // connector virtual balance
        uint32 weight;                  // connector weight, represented in ppm, 1-1000000
        bool isVirtualBalanceEnabled;   // true if virtual balance is enabled, false if not
        bool isSaleEnabled;             // is sale of the connector token enabled, can be set by the owner
        bool isSet;                     // used to tell if the mapping element is defined
    }

    /**
        @dev version number
    */
    uint16 public version = 14;
    string public converterType = 'bancor';

    bool public allowRegistryUpdate = true;             // allows the owner to prevent/allow the registry to be updated
    IContractRegistry public prevRegistry;              // address of previous registry as security mechanism
    IContractRegistry public registry;                  // contract registry contract
    IWhitelist public conversionWhitelist;              // whitelist contract with list of addresses that are allowed to use the converter
    IERC20Token[] public connectorTokens;               // ERC20 standard token addresses
    mapping (address => Connector) public connectors;   // connector token addresses -> connector data
    uint32 private totalConnectorWeight = 0;            // used to efficiently prevent increasing the total connector weight above 100%
    uint32 public maxConversionFee = 0;                 // maximum conversion fee for the lifetime of the contract,
                                                        // represented in ppm, 0...1000000 (0 = no fee, 100 = 0.01%, 1000000 = 100%)
    uint32 public conversionFee = 0;                    // current conversion fee, represented in ppm, 0...maxConversionFee
    bool public conversionsEnabled = true;              // true if token conversions is enabled, false if not
    IERC20Token[] private convertPath;

    /**
        @dev triggered when a conversion between two tokens occurs

        @param _fromToken       ERC20 token converted from
        @param _toToken         ERC20 token converted to
        @param _trader          wallet that initiated the trade
        @param _amount          amount converted, in fromToken
        @param _return          amount returned, minus conversion fee
        @param _conversionFee   conversion fee
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
        @dev triggered after a conversion with new price data

        @param  _connectorToken     connector token
        @param  _tokenSupply        smart token supply
        @param  _connectorBalance   connector balance
        @param  _connectorWeight    connector weight
    */
    event PriceDataUpdate(
        address indexed _connectorToken,
        uint256 _tokenSupply,
        uint256 _connectorBalance,
        uint32 _connectorWeight
    );

    /**
        @dev triggered when the conversion fee is updated

        @param  _prevFee    previous fee percentage, represented in ppm
        @param  _newFee     new fee percentage, represented in ppm
    */
    event ConversionFeeUpdate(uint32 _prevFee, uint32 _newFee);

    /**
        @dev triggered when conversions are enabled/disabled

        @param  _conversionsEnabled true if conversions are enabled, false if not
    */
    event ConversionsEnable(bool _conversionsEnabled);

    /**
        @dev initializes a new BancorConverter instance

        @param  _token              smart token governed by the converter
        @param  _registry           address of a contract registry contract
        @param  _maxConversionFee   maximum conversion fee, represented in ppm
        @param  _connectorToken     optional, initial connector, allows defining the first connector at deployment time
        @param  _connectorWeight    optional, weight for the initial connector
    */
    constructor(
        ISmartToken _token,
        IContractRegistry _registry,
        uint32 _maxConversionFee,
        IERC20Token _connectorToken,
        uint32 _connectorWeight
    )
        public
        SmartTokenController(_token)
        validAddress(_registry)
        validMaxConversionFee(_maxConversionFee)
    {
        registry = _registry;
        prevRegistry = _registry;
        IContractFeatures features = IContractFeatures(registry.addressOf(ContractIds.CONTRACT_FEATURES));

        // initialize supported features
        if (features != address(0))
            features.enableFeatures(FeatureIds.CONVERTER_CONVERSION_WHITELIST, true);

        maxConversionFee = _maxConversionFee;

        if (_connectorToken != address(0))
            addConnector(_connectorToken, _connectorWeight, false);
    }

    // validates a connector token address - verifies that the address belongs to one of the connector tokens
    modifier validConnector(IERC20Token _address) {
        require(connectors[_address].isSet);
        _;
    }

    // validates a token address - verifies that the address belongs to one of the convertible tokens
    modifier validToken(IERC20Token _address) {
        require(_address == token || connectors[_address].isSet);
        _;
    }

    // validates maximum conversion fee
    modifier validMaxConversionFee(uint32 _conversionFee) {
        require(_conversionFee >= 0 && _conversionFee <= MAX_CONVERSION_FEE);
        _;
    }

    // validates conversion fee
    modifier validConversionFee(uint32 _conversionFee) {
        require(_conversionFee >= 0 && _conversionFee <= maxConversionFee);
        _;
    }

    // validates connector weight range
    modifier validConnectorWeight(uint32 _weight) {
        require(_weight > 0 && _weight <= MAX_WEIGHT);
        _;
    }

    // validates a conversion path - verifies that the number of elements is odd and that maximum number of 'hops' is 10
    modifier validConversionPath(IERC20Token[] _path) {
        require(_path.length > 2 && _path.length <= (1 + 2 * 10) && _path.length % 2 == 1);
        _;
    }

    // allows execution only when the total weight is 100%
    modifier maxTotalWeightOnly() {
        require(totalConnectorWeight == MAX_WEIGHT);
        _;
    }

    // allows execution only when conversions aren't disabled
    modifier conversionsAllowed {
        assert(conversionsEnabled);
        _;
    }

    // allows execution by the BancorNetwork contract only
    modifier bancorNetworkOnly {
        IBancorNetwork bancorNetwork = IBancorNetwork(registry.addressOf(ContractIds.BANCOR_NETWORK));
        require(msg.sender == address(bancorNetwork));
        _;
    }

    // allows execution by the converter upgrader contract only
    modifier converterUpgraderOnly {
        address converterUpgrader = registry.addressOf(ContractIds.BANCOR_CONVERTER_UPGRADER);
        require(owner == converterUpgrader);
        _;
    }

    /**
        @dev sets the contract registry to whichever address the current registry is pointing to
     */
    function updateRegistry() public {
        // require that upgrading is allowed or that the caller is the owner
        require(allowRegistryUpdate || msg.sender == owner);

        // get the address of whichever registry the current registry is pointing to
        address newRegistry = registry.addressOf(ContractIds.CONTRACT_REGISTRY);

        // if the new registry hasn't changed or is the zero address, revert
        require(newRegistry != address(registry) && newRegistry != address(0));

        // set the previous registry as current registry and current registry as newRegistry
        prevRegistry = registry;
        registry = IContractRegistry(newRegistry);
    }

    /**
        @dev security mechanism allowing the converter owner to revert to the previous registry,
        to be used in emergency scenario
    */
    function restoreRegistry() public ownerOrManagerOnly {
        // set the registry as previous registry
        registry = prevRegistry;

        // after a previous registry is restored, only the owner can allow future updates
        allowRegistryUpdate = false;
    }

    /**
        @dev disables the registry update functionality
        this is a safety mechanism in case of a emergency
        can only be called by the manager or owner

        @param _disable    true to disable registry updates, false to re-enable them
    */
    function disableRegistryUpdate(bool _disable) public ownerOrManagerOnly {
        allowRegistryUpdate = !_disable;
    }

    /**
        @dev returns the number of connector tokens defined

        @return number of connector tokens
    */
    function connectorTokenCount() public view returns (uint16) {
        return uint16(connectorTokens.length);
    }

    /**
        @dev allows the owner to update & enable the conversion whitelist contract address
        when set, only addresses that are whitelisted are actually allowed to use the converter
        note that the whitelist check is actually done by the BancorNetwork contract

        @param _whitelist    address of a whitelist contract
    */
    function setConversionWhitelist(IWhitelist _whitelist)
        public
        ownerOnly
        notThis(_whitelist)
    {
        conversionWhitelist = _whitelist;
    }

    /**
        @dev disables the entire conversion functionality
        this is a safety mechanism in case of a emergency
        can only be called by the manager

        @param _disable true to disable conversions, false to re-enable them
    */
    function disableConversions(bool _disable) public ownerOrManagerOnly {
        if (conversionsEnabled == _disable) {
            conversionsEnabled = !_disable;
            emit ConversionsEnable(conversionsEnabled);
        }
    }

    /**
        @dev allows transferring the token ownership
        the new owner needs to accept the transfer
        can only be called by the contract owner
        note that token ownership can only be transferred while the owner is the converter upgrader contract

        @param _newOwner    new token owner
    */
    function transferTokenOwnership(address _newOwner)
        public
        ownerOnly
        converterUpgraderOnly
    {
        super.transferTokenOwnership(_newOwner);
    }

    /**
        @dev updates the current conversion fee
        can only be called by the manager

        @param _conversionFee new conversion fee, represented in ppm
    */
    function setConversionFee(uint32 _conversionFee)
        public
        ownerOrManagerOnly
        validConversionFee(_conversionFee)
    {
        emit ConversionFeeUpdate(conversionFee, _conversionFee);
        conversionFee = _conversionFee;
    }

    /**
        @dev given a return amount, returns the amount minus the conversion fee

        @param _amount      return amount
        @param _magnitude   1 for standard conversion, 2 for cross connector conversion

        @return return amount minus conversion fee
    */
    function getFinalAmount(uint256 _amount, uint8 _magnitude) public view returns (uint256) {
        return _amount.mul((MAX_CONVERSION_FEE - conversionFee) ** _magnitude).div(MAX_CONVERSION_FEE ** _magnitude);
    }

    /**
        @dev withdraws tokens held by the converter and sends them to an account
        can only be called by the owner
        note that connector tokens can only be withdrawn by the owner while the converter is inactive
        unless the owner is the converter upgrader contract

        @param _token   ERC20 token contract address
        @param _to      account to receive the new amount
        @param _amount  amount to withdraw
    */
    function withdrawTokens(IERC20Token _token, address _to, uint256 _amount) public {
        address converterUpgrader = registry.addressOf(ContractIds.BANCOR_CONVERTER_UPGRADER);

        // if the token is not a connector token, allow withdrawal
        // otherwise verify that the converter is inactive or that the owner is the upgrader contract
        require(!connectors[_token].isSet || token.owner() != address(this) || owner == converterUpgrader);
        super.withdrawTokens(_token, _to, _amount);
    }

    /**
        @dev upgrades the converter to the latest version
        can only be called by the owner
        note that the owner needs to call acceptOwnership/acceptManagement on the new converter after the upgrade
    */
    function upgrade() public ownerOnly {
        IBancorConverterUpgrader converterUpgrader = IBancorConverterUpgrader(registry.addressOf(ContractIds.BANCOR_CONVERTER_UPGRADER));

        transferOwnership(converterUpgrader);
        converterUpgrader.upgrade(version);
        acceptOwnership();
    }

    /**
        @dev defines a new connector for the token
        can only be called by the owner while the converter is inactive

        @param _token                  address of the connector token
        @param _weight                 constant connector weight, represented in ppm, 1-1000000
        @param _enableVirtualBalance   true to enable virtual balance for the connector, false to disable it
    */
    function addConnector(IERC20Token _token, uint32 _weight, bool _enableVirtualBalance)
        public
        ownerOnly
        inactive
        validAddress(_token)
        notThis(_token)
        validConnectorWeight(_weight)
    {
        require(_token != token && !connectors[_token].isSet && totalConnectorWeight + _weight <= MAX_WEIGHT); // validate input

        connectors[_token].virtualBalance = 0;
        connectors[_token].weight = _weight;
        connectors[_token].isVirtualBalanceEnabled = _enableVirtualBalance;
        connectors[_token].isSaleEnabled = true;
        connectors[_token].isSet = true;
        connectorTokens.push(_token);
        totalConnectorWeight += _weight;
    }

    /**
        @dev updates one of the token connectors
        can only be called by the owner

        @param _connectorToken         address of the connector token
        @param _weight                 constant connector weight, represented in ppm, 1-1000000
        @param _enableVirtualBalance   true to enable virtual balance for the connector, false to disable it
        @param _virtualBalance         new connector's virtual balance
    */
    function updateConnector(IERC20Token _connectorToken, uint32 _weight, bool _enableVirtualBalance, uint256 _virtualBalance)
        public
        ownerOnly
        validConnector(_connectorToken)
        validConnectorWeight(_weight)
    {
        Connector storage connector = connectors[_connectorToken];
        require(totalConnectorWeight - connector.weight + _weight <= MAX_WEIGHT); // validate input

        totalConnectorWeight = totalConnectorWeight - connector.weight + _weight;
        connector.weight = _weight;
        connector.isVirtualBalanceEnabled = _enableVirtualBalance;
        connector.virtualBalance = _virtualBalance;
    }

    /**
        @dev disables converting from the given connector token in case the connector token got compromised
        can only be called by the owner
        note that converting to the token is still enabled regardless of this flag and it cannot be disabled by the owner

        @param _connectorToken  connector token contract address
        @param _disable         true to disable the token, false to re-enable it
    */
    function disableConnectorSale(IERC20Token _connectorToken, bool _disable)
        public
        ownerOnly
        validConnector(_connectorToken)
    {
        connectors[_connectorToken].isSaleEnabled = !_disable;
    }

    /**
        @dev returns the connector's virtual balance if one is defined, otherwise returns the actual balance

        @param _connectorToken  connector token contract address

        @return connector balance
    */
    function getConnectorBalance(IERC20Token _connectorToken)
        public
        view
        validConnector(_connectorToken)
        returns (uint256)
    {
        Connector storage connector = connectors[_connectorToken];
        return connector.isVirtualBalanceEnabled ? connector.virtualBalance : _connectorToken.balanceOf(this);
    }

    /**
        @dev returns the expected return for converting a specific amount of _fromToken to _toToken

        @param _fromToken  ERC20 token to convert from
        @param _toToken    ERC20 token to convert to
        @param _amount     amount to convert, in fromToken

        @return expected conversion return amount and conversion fee
    */
    function getReturn(IERC20Token _fromToken, IERC20Token _toToken, uint256 _amount) public view returns (uint256, uint256) {
        require(_fromToken != _toToken); // validate input

        // conversion between the token and one of its connectors
        if (_toToken == token)
            return getPurchaseReturn(_fromToken, _amount);
        else if (_fromToken == token)
            return getSaleReturn(_toToken, _amount);

        // conversion between 2 connectors
        return getCrossConnectorReturn(_fromToken, _toToken, _amount);
    }

    /**
        @dev returns the expected return for buying the token for a connector token

        @param _connectorToken  connector token contract address
        @param _depositAmount   amount to deposit (in the connector token)

        @return expected purchase return amount and conversion fee
    */
    function getPurchaseReturn(IERC20Token _connectorToken, uint256 _depositAmount)
        public
        view
        active
        validConnector(_connectorToken)
        returns (uint256, uint256)
    {
        Connector storage connector = connectors[_connectorToken];
        require(connector.isSaleEnabled); // validate input

        uint256 tokenSupply = token.totalSupply();
        uint256 connectorBalance = getConnectorBalance(_connectorToken);
        IBancorFormula formula = IBancorFormula(registry.addressOf(ContractIds.BANCOR_FORMULA));
        uint256 amount = formula.calculatePurchaseReturn(tokenSupply, connectorBalance, connector.weight, _depositAmount);
        uint256 finalAmount = getFinalAmount(amount, 1);

        // return the amount minus the conversion fee and the conversion fee
        return (finalAmount, amount - finalAmount);
    }

    /**
        @dev returns the expected return for selling the token for one of its connector tokens

        @param _connectorToken  connector token contract address
        @param _sellAmount      amount to sell (in the smart token)

        @return expected sale return amount and conversion fee
    */
    function getSaleReturn(IERC20Token _connectorToken, uint256 _sellAmount)
        public
        view
        active
        validConnector(_connectorToken)
        returns (uint256, uint256)
    {
        Connector storage connector = connectors[_connectorToken];
        uint256 tokenSupply = token.totalSupply();
        uint256 connectorBalance = getConnectorBalance(_connectorToken);
        IBancorFormula formula = IBancorFormula(registry.addressOf(ContractIds.BANCOR_FORMULA));
        uint256 amount = formula.calculateSaleReturn(tokenSupply, connectorBalance, connector.weight, _sellAmount);
        uint256 finalAmount = getFinalAmount(amount, 1);

        // return the amount minus the conversion fee and the conversion fee
        return (finalAmount, amount - finalAmount);
    }

    /**
        @dev returns the expected return for selling one of the connector tokens for another connector token

        @param _fromConnectorToken  contract address of the connector token to convert from
        @param _toConnectorToken    contract address of the connector token to convert to
        @param _sellAmount          amount to sell (in the from connector token)

        @return expected sale return amount and conversion fee (in the to connector token)
    */
    function getCrossConnectorReturn(IERC20Token _fromConnectorToken, IERC20Token _toConnectorToken, uint256 _sellAmount)
        public
        view
        active
        validConnector(_fromConnectorToken)
        validConnector(_toConnectorToken)
        returns (uint256, uint256)
    {
        Connector storage fromConnector = connectors[_fromConnectorToken];
        Connector storage toConnector = connectors[_toConnectorToken];
        require(fromConnector.isSaleEnabled); // validate input

        IBancorFormula formula = IBancorFormula(registry.addressOf(ContractIds.BANCOR_FORMULA));
        uint256 amount = formula.calculateCrossConnectorReturn(
            getConnectorBalance(_fromConnectorToken), 
            fromConnector.weight, 
            getConnectorBalance(_toConnectorToken), 
            toConnector.weight, 
            _sellAmount);
        uint256 finalAmount = getFinalAmount(amount, 2);

        // return the amount minus the conversion fee and the conversion fee
        // the fee is higher (magnitude = 2) since cross connector conversion equals 2 conversions (from / to the smart token)
        return (finalAmount, amount - finalAmount);
    }

    /**
        @dev converts a specific amount of _fromToken to _toToken
        can only be called by the bancor network contract

        @param _fromToken  ERC20 token to convert from
        @param _toToken    ERC20 token to convert to
        @param _amount     amount to convert, in fromToken
        @param _minReturn  if the conversion results in an amount smaller than the minimum return - it is cancelled, must be nonzero

        @return conversion return amount
    */
    function convertInternal(IERC20Token _fromToken, IERC20Token _toToken, uint256 _amount, uint256 _minReturn)
        public
        bancorNetworkOnly
        conversionsAllowed
        greaterThanZero(_minReturn)
        returns (uint256)
    {
        require(_fromToken != _toToken); // validate input

        // conversion between the token and one of its connectors
        if (_toToken == token)
            return buy(_fromToken, _amount, _minReturn);
        else if (_fromToken == token)
            return sell(_toToken, _amount, _minReturn);

        uint256 amount;
        uint256 feeAmount;

        // conversion between 2 connectors
        (amount, feeAmount) = getCrossConnectorReturn(_fromToken, _toToken, _amount);
        // ensure the trade gives something in return and meets the minimum requested amount
        require(amount != 0 && amount >= _minReturn);

        // update the source token virtual balance if relevant
        Connector storage fromConnector = connectors[_fromToken];
        if (fromConnector.isVirtualBalanceEnabled)
            fromConnector.virtualBalance = fromConnector.virtualBalance.add(_amount);

        // update the target token virtual balance if relevant
        Connector storage toConnector = connectors[_toToken];
        if (toConnector.isVirtualBalanceEnabled)
            toConnector.virtualBalance = toConnector.virtualBalance.sub(amount);

        // ensure that the trade won't deplete the connector balance
        uint256 toConnectorBalance = getConnectorBalance(_toToken);
        assert(amount < toConnectorBalance);

        // transfer funds from the caller in the from connector token
        ensureTransferFrom(_fromToken, msg.sender, this, _amount);
        // transfer funds to the caller in the to connector token
        // the transfer might fail if the actual connector balance is smaller than the virtual balance
        ensureTransfer(_toToken, msg.sender, amount);

        // dispatch the conversion event
        // the fee is higher (magnitude = 2) since cross connector conversion equals 2 conversions (from / to the smart token)
        dispatchConversionEvent(_fromToken, _toToken, _amount, amount, feeAmount);

        // dispatch price data updates for the smart token / both connectors
        emit PriceDataUpdate(_fromToken, token.totalSupply(), getConnectorBalance(_fromToken), fromConnector.weight);
        emit PriceDataUpdate(_toToken, token.totalSupply(), getConnectorBalance(_toToken), toConnector.weight);
        return amount;
    }

    /**
        @dev converts a specific amount of _fromToken to _toToken

        @param _fromToken  ERC20 token to convert from
        @param _toToken    ERC20 token to convert to
        @param _amount     amount to convert, in fromToken
        @param _minReturn  if the conversion results in an amount smaller than the minimum return - it is cancelled, must be nonzero

        @return conversion return amount
    */
    function convert(IERC20Token _fromToken, IERC20Token _toToken, uint256 _amount, uint256 _minReturn) public returns (uint256) {
        convertPath = [_fromToken, token, _toToken];
        return quickConvert(convertPath, _amount, _minReturn);
    }

    /**
        @dev buys the token by depositing one of its connector tokens

        @param _connectorToken  connector token contract address
        @param _depositAmount   amount to deposit (in the connector token)
        @param _minReturn       if the conversion results in an amount smaller than the minimum return - it is cancelled, must be nonzero

        @return buy return amount
    */
    function buy(IERC20Token _connectorToken, uint256 _depositAmount, uint256 _minReturn) internal returns (uint256) {
        uint256 amount;
        uint256 feeAmount;
        (amount, feeAmount) = getPurchaseReturn(_connectorToken, _depositAmount);
        // ensure the trade gives something in return and meets the minimum requested amount
        require(amount != 0 && amount >= _minReturn);

        // update virtual balance if relevant
        Connector storage connector = connectors[_connectorToken];
        if (connector.isVirtualBalanceEnabled)
            connector.virtualBalance = connector.virtualBalance.add(_depositAmount);

        // transfer funds from the caller in the connector token
        ensureTransferFrom(_connectorToken, msg.sender, this, _depositAmount);
        // issue new funds to the caller in the smart token
        token.issue(msg.sender, amount);

        // dispatch the conversion event
        dispatchConversionEvent(_connectorToken, token, _depositAmount, amount, feeAmount);

        // dispatch price data update for the smart token/connector
        emit PriceDataUpdate(_connectorToken, token.totalSupply(), getConnectorBalance(_connectorToken), connector.weight);
        return amount;
    }

    /**
        @dev sells the token by withdrawing from one of its connector tokens

        @param _connectorToken  connector token contract address
        @param _sellAmount      amount to sell (in the smart token)
        @param _minReturn       if the conversion results in an amount smaller the minimum return - it is cancelled, must be nonzero

        @return sell return amount
    */
    function sell(IERC20Token _connectorToken, uint256 _sellAmount, uint256 _minReturn) internal returns (uint256) {
        require(_sellAmount <= token.balanceOf(msg.sender)); // validate input
        uint256 amount;
        uint256 feeAmount;
        (amount, feeAmount) = getSaleReturn(_connectorToken, _sellAmount);
        // ensure the trade gives something in return and meets the minimum requested amount
        require(amount != 0 && amount >= _minReturn);

        // ensure that the trade will only deplete the connector balance if the total supply is depleted as well
        uint256 tokenSupply = token.totalSupply();
        uint256 connectorBalance = getConnectorBalance(_connectorToken);
        assert(amount < connectorBalance || (amount == connectorBalance && _sellAmount == tokenSupply));

        // update virtual balance if relevant
        Connector storage connector = connectors[_connectorToken];
        if (connector.isVirtualBalanceEnabled)
            connector.virtualBalance = connector.virtualBalance.sub(amount);

        // destroy _sellAmount from the caller's balance in the smart token
        token.destroy(msg.sender, _sellAmount);
        // transfer funds to the caller in the connector token
        // the transfer might fail if the actual connector balance is smaller than the virtual balance
        ensureTransfer(_connectorToken, msg.sender, amount);

        // dispatch the conversion event
        dispatchConversionEvent(token, _connectorToken, _sellAmount, amount, feeAmount);

        // dispatch price data update for the smart token/connector
        emit PriceDataUpdate(_connectorToken, token.totalSupply(), getConnectorBalance(_connectorToken), connector.weight);
        return amount;
    }

    /**
        @dev converts the token to any other token in the bancor network by following a predefined conversion path
        note that when converting from an ERC20 token (as opposed to a smart token), allowance must be set beforehand

        @param _path        conversion path, see conversion path format in the BancorNetwork contract
        @param _amount      amount to convert from (in the initial source token)
        @param _minReturn   if the conversion results in an amount smaller than the minimum return - it is cancelled, must be nonzero

        @return tokens issued in return
    */
    function quickConvert(IERC20Token[] _path, uint256 _amount, uint256 _minReturn)
        public
        payable
        returns (uint256)
    {
        return quickConvertPrioritized(_path, _amount, _minReturn, 0x0, 0x0, 0x0, 0x0);
    }

    /**
        @dev converts the token to any other token in the bancor network by following a predefined conversion path
        note that when converting from an ERC20 token (as opposed to a smart token), allowance must be set beforehand

        @param _path        conversion path, see conversion path format in the BancorNetwork contract
        @param _amount      amount to convert from (in the initial source token)
        @param _minReturn   if the conversion results in an amount smaller than the minimum return - it is cancelled, must be nonzero
        @param _block       if the current block exceeded the given parameter - it is cancelled
        @param _v           (signature[128:130]) associated with the signer address and helps validating if the signature is legit
        @param _r           (signature[0:64]) associated with the signer address and helps validating if the signature is legit
        @param _s           (signature[64:128]) associated with the signer address and helps validating if the signature is legit

        @return tokens issued in return
    */
    function quickConvertPrioritized(IERC20Token[] _path, uint256 _amount, uint256 _minReturn, uint256 _block, uint8 _v, bytes32 _r, bytes32 _s)
        public
        payable
        returns (uint256)
    {
        IERC20Token fromToken = _path[0];
        IBancorNetwork bancorNetwork = IBancorNetwork(registry.addressOf(ContractIds.BANCOR_NETWORK));

        // we need to transfer the source tokens from the caller to the BancorNetwork contract,
        // so it can execute the conversion on behalf of the caller
        if (msg.value == 0) {
            // not ETH, send the source tokens to the BancorNetwork contract
            // if the token is the smart token, no allowance is required - destroy the tokens
            // from the caller and issue them to the BancorNetwork contract
            if (fromToken == token) {
                token.destroy(msg.sender, _amount); // destroy _amount tokens from the caller's balance in the smart token
                token.issue(bancorNetwork, _amount); // issue _amount new tokens to the BancorNetwork contract
            } else {
                // otherwise, we assume we already have allowance, transfer the tokens directly to the BancorNetwork contract
                ensureTransferFrom(fromToken, msg.sender, bancorNetwork, _amount);
            }
        }

        // execute the conversion and pass on the ETH with the call
        return bancorNetwork.convertForPrioritized3.value(msg.value)(_path, _amount, _minReturn, msg.sender, _amount, _block, _v, _r, _s);
    }

    /**
        @dev allows a user to convert BNT that was sent from another blockchain into any other
        token on the BancorNetwork without specifying the amount of BNT to be converted, but
        rather by providing the xTransferId which allows us to get the amount from BancorX.

        @param _path             conversion path, see conversion path format in the BancorNetwork contract
        @param _minReturn        if the conversion results in an amount smaller than the minimum return - it is cancelled, must be nonzero
        @param _conversionId     pre-determined unique (if non zero) id which refers to this transaction 
        @param _block            if the current block exceeded the given parameter - it is cancelled
        @param _v                (signature[128:130]) associated with the signer address and helps to validate if the signature is legit
        @param _r                (signature[0:64]) associated with the signer address and helps to validate if the signature is legit
        @param _s                (signature[64:128]) associated with the signer address and helps to validate if the signature is legit

        @return tokens issued in return
    */
    function completeXConversion(
        IERC20Token[] _path,
        uint256 _minReturn,
        uint256 _conversionId,
        uint256 _block,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    )
        public
        returns (uint256)
    {
        IBancorX bancorX = IBancorX(registry.addressOf(ContractIds.BANCOR_X));
        IBancorNetwork bancorNetwork = IBancorNetwork(registry.addressOf(ContractIds.BANCOR_NETWORK));

        // verify that the first token in the path is BNT
        require(_path[0] == registry.addressOf(ContractIds.BNT_TOKEN));

        // get conversion amount from BancorX contract
        uint256 amount = bancorX.getXTransferAmount(_conversionId, msg.sender);

        // send BNT from msg.sender to the BancorNetwork contract
        token.destroy(msg.sender, amount);
        token.issue(bancorNetwork, amount);

        return bancorNetwork.convertForPrioritized3(_path, amount, _minReturn, msg.sender, _conversionId, _block, _v, _r, _s);
    }

    /**
        @dev ensures transfer of tokens, taking into account that some ERC-20 implementations don't return
        true on success but revert on failure instead

        @param _token     the token to transfer
        @param _to        the address to transfer the tokens to
        @param _amount    the amount to transfer
    */
    function ensureTransfer(IERC20Token _token, address _to, uint256 _amount) private {
        IAddressList addressList = IAddressList(registry.addressOf(ContractIds.NON_STANDARD_TOKEN_REGISTRY));

        if (addressList.listedAddresses(_token)) {
            uint256 prevBalance = _token.balanceOf(_to);
            // we have to cast the token contract in an interface which has no return value
            INonStandardERC20(_token).transfer(_to, _amount);
            uint256 postBalance = _token.balanceOf(_to);
            assert(postBalance > prevBalance);
        } else {
            // if the token isn't whitelisted, we assert on transfer
            assert(_token.transfer(_to, _amount));
        }
    }

    /**
        @dev ensures transfer of tokens, taking into account that some ERC-20 implementations don't return
        true on success but revert on failure instead

        @param _token     the token to transfer
        @param _from      the address to transfer the tokens from
        @param _to        the address to transfer the tokens to
        @param _amount    the amount to transfer
    */
    function ensureTransferFrom(IERC20Token _token, address _from, address _to, uint256 _amount) private {
        IAddressList addressList = IAddressList(registry.addressOf(ContractIds.NON_STANDARD_TOKEN_REGISTRY));

        if (addressList.listedAddresses(_token)) {
            uint256 prevBalance = _token.balanceOf(_to);
            // we have to cast the token contract in an interface which has no return value
            INonStandardERC20(_token).transferFrom(_from, _to, _amount);
            uint256 postBalance = _token.balanceOf(_to);
            assert(postBalance > prevBalance);
        } else {
            // if the token is standard, we assert on transfer
            assert(_token.transferFrom(_from, _to, _amount));
        }
    }

    /**
        @dev buys the token with all connector tokens using the same percentage
        i.e. if the caller increases the supply by 10%, it will cost an amount equal to
        10% of each connector token balance
        can only be called if the max total weight is exactly 100% and while conversions are enabled

        @param _amount  amount to increase the supply by (in the smart token)
    */
    function fund(uint256 _amount)
        public
        maxTotalWeightOnly
        conversionsAllowed
    {
        uint256 supply = token.totalSupply();

        // iterate through the connector tokens and transfer a percentage equal to the ratio between _amount
        // and the total supply in each connector from the caller to the converter
        IERC20Token connectorToken;
        uint256 connectorBalance;
        uint256 connectorAmount;
        for (uint16 i = 0; i < connectorTokens.length; i++) {
            connectorToken = connectorTokens[i];
            connectorBalance = getConnectorBalance(connectorToken);
            connectorAmount = _amount.mul(connectorBalance).sub(1).div(supply).add(1);

            // update virtual balance if relevant
            Connector storage connector = connectors[connectorToken];
            if (connector.isVirtualBalanceEnabled)
                connector.virtualBalance = connector.virtualBalance.add(connectorAmount);

            // transfer funds from the caller in the connector token
            ensureTransferFrom(connectorToken, msg.sender, this, connectorAmount);

            // dispatch price data update for the smart token/connector
            emit PriceDataUpdate(connectorToken, supply + _amount, connectorBalance + connectorAmount, connector.weight);
        }

        // issue new funds to the caller in the smart token
        token.issue(msg.sender, _amount);
    }

    /**
        @dev sells the token for all connector tokens using the same percentage
        i.e. if the holder sells 10% of the supply, they will receive 10% of each
        connector token balance in return
        can only be called if the max total weight is exactly 100%
        note that the function can also be called if conversions are disabled

        @param _amount  amount to liquidate (in the smart token)
    */
    function liquidate(uint256 _amount) public maxTotalWeightOnly {
        uint256 supply = token.totalSupply();

        // destroy _amount from the caller's balance in the smart token
        token.destroy(msg.sender, _amount);

        // iterate through the connector tokens and send a percentage equal to the ratio between _amount
        // and the total supply from each connector balance to the caller
        IERC20Token connectorToken;
        uint256 connectorBalance;
        uint256 connectorAmount;
        for (uint16 i = 0; i < connectorTokens.length; i++) {
            connectorToken = connectorTokens[i];
            connectorBalance = getConnectorBalance(connectorToken);
            connectorAmount = _amount.mul(connectorBalance).div(supply);

            // update virtual balance if relevant
            Connector storage connector = connectors[connectorToken];
            if (connector.isVirtualBalanceEnabled)
                connector.virtualBalance = connector.virtualBalance.sub(connectorAmount);

            // transfer funds to the caller in the connector token
            // the transfer might fail if the actual connector balance is smaller than the virtual balance
            ensureTransfer(connectorToken, msg.sender, connectorAmount);

            // dispatch price data update for the smart token/connector
            emit PriceDataUpdate(connectorToken, supply - _amount, connectorBalance - connectorAmount, connector.weight);
        }
    }

    /**
        @dev deprecated, backward compatibility
    */
    function change(IERC20Token _fromToken, IERC20Token _toToken, uint256 _amount, uint256 _minReturn) public returns (uint256) {
        return convertInternal(_fromToken, _toToken, _amount, _minReturn);
    }

    /**
        @dev helper, dispatches the Conversion event

        @param _fromToken       ERC20 token to convert from
        @param _toToken         ERC20 token to convert to
        @param _amount          amount purchased/sold (in the source token)
        @param _returnAmount    amount returned (in the target token)
    */
    function dispatchConversionEvent(IERC20Token _fromToken, IERC20Token _toToken, uint256 _amount, uint256 _returnAmount, uint256 _feeAmount) private {
        // fee amount is converted to 255 bits -
        // negative amount means the fee is taken from the source token, positive amount means its taken from the target token
        // currently the fee is always taken from the target token
        // since we convert it to a signed number, we first ensure that it's capped at 255 bits to prevent overflow
        assert(_feeAmount <= 2 ** 255);
        emit Conversion(_fromToken, _toToken, msg.sender, _amount, _returnAmount, int256(_feeAmount));
    }
}
