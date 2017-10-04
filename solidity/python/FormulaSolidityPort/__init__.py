version = '0.2';

MAX_CRR = 1000000;
ONE = 1;
MIN_PRECISION = 32;
MAX_PRECISION = 127;

'''
    The values below depend on MAX_PRECISION. If you choose to change it:
    Apply the same change in file 'PrintIntScalingFactors.py', run it and paste the results below.
'''
FIXED_1 = 0x080000000000000000000000000000000;
FIXED_2 = 0x100000000000000000000000000000000;
MAX_NUM = 0x1ffffffffffffffffffffffffffffffff;

'''
    The values below depend on MAX_PRECISION. If you choose to change it:
    Apply the same change in file 'PrintLn2ScalingFactors.py', run it and paste the results below.
'''
LN2_MANTISSA = 0x2c5c85fdf473de6af278ece600fcbda;
LN2_EXPONENT = 122;

'''
    The values below depend on MIN_PRECISION and MAX_PRECISION. If you choose to change either one of them:
    Apply the same change in file 'PrintFunctionBancorFormula.py', run it and paste the results below.
'''
maxExpArray = [0] * 128;

def BancorFormula():
#   maxExpArray[  0] = 0x6bffffffffffffffffffffffffffffffff;
#   maxExpArray[  1] = 0x67ffffffffffffffffffffffffffffffff;
#   maxExpArray[  2] = 0x637fffffffffffffffffffffffffffffff;
#   maxExpArray[  3] = 0x5f6fffffffffffffffffffffffffffffff;
#   maxExpArray[  4] = 0x5b77ffffffffffffffffffffffffffffff;
#   maxExpArray[  5] = 0x57b3ffffffffffffffffffffffffffffff;
#   maxExpArray[  6] = 0x5419ffffffffffffffffffffffffffffff;
#   maxExpArray[  7] = 0x50a2ffffffffffffffffffffffffffffff;
#   maxExpArray[  8] = 0x4d517fffffffffffffffffffffffffffff;
#   maxExpArray[  9] = 0x4a233fffffffffffffffffffffffffffff;
#   maxExpArray[ 10] = 0x47165fffffffffffffffffffffffffffff;
#   maxExpArray[ 11] = 0x4429afffffffffffffffffffffffffffff;
#   maxExpArray[ 12] = 0x415bc7ffffffffffffffffffffffffffff;
#   maxExpArray[ 13] = 0x3eab73ffffffffffffffffffffffffffff;
#   maxExpArray[ 14] = 0x3c1771ffffffffffffffffffffffffffff;
#   maxExpArray[ 15] = 0x399e96ffffffffffffffffffffffffffff;
#   maxExpArray[ 16] = 0x373fc47fffffffffffffffffffffffffff;
#   maxExpArray[ 17] = 0x34f9e8ffffffffffffffffffffffffffff;
#   maxExpArray[ 18] = 0x32cbfd5fffffffffffffffffffffffffff;
#   maxExpArray[ 19] = 0x30b5057fffffffffffffffffffffffffff;
#   maxExpArray[ 20] = 0x2eb40f9fffffffffffffffffffffffffff;
#   maxExpArray[ 21] = 0x2cc8340fffffffffffffffffffffffffff;
#   maxExpArray[ 22] = 0x2af09481ffffffffffffffffffffffffff;
#   maxExpArray[ 23] = 0x292c5bddffffffffffffffffffffffffff;
#   maxExpArray[ 24] = 0x277abdcdffffffffffffffffffffffffff;
#   maxExpArray[ 25] = 0x25daf6657fffffffffffffffffffffffff;
#   maxExpArray[ 26] = 0x244c49c65fffffffffffffffffffffffff;
#   maxExpArray[ 27] = 0x22ce03cd5fffffffffffffffffffffffff;
#   maxExpArray[ 28] = 0x215f77c047ffffffffffffffffffffffff;
#   maxExpArray[ 29] = 0x1fffffffffffffffffffffffffffffffff;
#   maxExpArray[ 30] = 0x1eaefdbdabffffffffffffffffffffffff;
#   maxExpArray[ 31] = 0x1d6bd8b2ebffffffffffffffffffffffff;
    maxExpArray[ 32] = 0x1c35fedd14ffffffffffffffffffffffff;
    maxExpArray[ 33] = 0x1b0ce43b323fffffffffffffffffffffff;
    maxExpArray[ 34] = 0x19f0028ec1ffffffffffffffffffffffff;
    maxExpArray[ 35] = 0x18ded91f0e7fffffffffffffffffffffff;
    maxExpArray[ 36] = 0x17d8ec7f0417ffffffffffffffffffffff;
    maxExpArray[ 37] = 0x16ddc6556cdbffffffffffffffffffffff;
    maxExpArray[ 38] = 0x15ecf52776a1ffffffffffffffffffffff;
    maxExpArray[ 39] = 0x15060c256cb2ffffffffffffffffffffff;
    maxExpArray[ 40] = 0x1428a2f98d72ffffffffffffffffffffff;
    maxExpArray[ 41] = 0x13545598e5c23fffffffffffffffffffff;
    maxExpArray[ 42] = 0x1288c4161ce1dfffffffffffffffffffff;
    maxExpArray[ 43] = 0x11c592761c666fffffffffffffffffffff;
    maxExpArray[ 44] = 0x110a688680a757ffffffffffffffffffff;
    maxExpArray[ 45] = 0x1056f1b5bedf77ffffffffffffffffffff;
    maxExpArray[ 46] = 0x0faadceceeff8bffffffffffffffffffff;
    maxExpArray[ 47] = 0x0f05dc6b27edadffffffffffffffffffff;
    maxExpArray[ 48] = 0x0e67a5a25da4107fffffffffffffffffff;
    maxExpArray[ 49] = 0x0dcff115b14eedffffffffffffffffffff;
    maxExpArray[ 50] = 0x0d3e7a392431239fffffffffffffffffff;
    maxExpArray[ 51] = 0x0cb2ff529eb71e4fffffffffffffffffff;
    maxExpArray[ 52] = 0x0c2d415c3db974afffffffffffffffffff;
    maxExpArray[ 53] = 0x0bad03e7d883f69bffffffffffffffffff;
    maxExpArray[ 54] = 0x0b320d03b2c343d5ffffffffffffffffff;
    maxExpArray[ 55] = 0x0abc25204e02828dffffffffffffffffff;
    maxExpArray[ 56] = 0x0a4b16f74ee4bb207fffffffffffffffff;
    maxExpArray[ 57] = 0x09deaf736ac1f569ffffffffffffffffff;
    maxExpArray[ 58] = 0x0976bd9952c7aa957fffffffffffffffff;
    maxExpArray[ 59] = 0x09131271922eaa606fffffffffffffffff;
    maxExpArray[ 60] = 0x08b380f3558668c46fffffffffffffffff;
    maxExpArray[ 61] = 0x0857ddf0117efa215bffffffffffffffff;
    maxExpArray[ 62] = 0x07ffffffffffffffffffffffffffffffff;
    maxExpArray[ 63] = 0x07abbf6f6abb9d087fffffffffffffffff;
    maxExpArray[ 64] = 0x075af62cbac95f7dfa7fffffffffffffff;
    maxExpArray[ 65] = 0x070d7fb7452e187ac13fffffffffffffff;
    maxExpArray[ 66] = 0x06c3390ecc8af379295fffffffffffffff;
    maxExpArray[ 67] = 0x067c00a3b07ffc01fd6fffffffffffffff;
    maxExpArray[ 68] = 0x0637b647c39cbb9d3d27ffffffffffffff;
    maxExpArray[ 69] = 0x05f63b1fc104dbd39587ffffffffffffff;
    maxExpArray[ 70] = 0x05b771955b36e12f7235ffffffffffffff;
    maxExpArray[ 71] = 0x057b3d49dda84556d6f6ffffffffffffff;
    maxExpArray[ 72] = 0x054183095b2c8ececf30ffffffffffffff;
    maxExpArray[ 73] = 0x050a28be635ca2b888f77fffffffffffff;
    maxExpArray[ 74] = 0x04d5156639708c9db33c3fffffffffffff;
    maxExpArray[ 75] = 0x04a23105873875bd52dfdfffffffffffff;
    maxExpArray[ 76] = 0x0471649d87199aa990756fffffffffffff;
    maxExpArray[ 77] = 0x04429a21a029d4c1457cfbffffffffffff;
    maxExpArray[ 78] = 0x0415bc6d6fb7dd71af2cb3ffffffffffff;
    maxExpArray[ 79] = 0x03eab73b3bbfe282243ce1ffffffffffff;
    maxExpArray[ 80] = 0x03c1771ac9fb6b4c18e229ffffffffffff;
    maxExpArray[ 81] = 0x0399e96897690418f785257fffffffffff;
    maxExpArray[ 82] = 0x0373fc456c53bb779bf0ea9fffffffffff;
    maxExpArray[ 83] = 0x034f9e8e490c48e67e6ab8bfffffffffff;
    maxExpArray[ 84] = 0x032cbfd4a7adc790560b3337ffffffffff;
    maxExpArray[ 85] = 0x030b50570f6e5d2acca94613ffffffffff;
    maxExpArray[ 86] = 0x02eb40f9f620fda6b56c2861ffffffffff;
    maxExpArray[ 87] = 0x02cc8340ecb0d0f520a6af58ffffffffff;
    maxExpArray[ 88] = 0x02af09481380a0a35cf1ba02ffffffffff;
    maxExpArray[ 89] = 0x0292c5bdd3b92ec810287b1b3fffffffff;
    maxExpArray[ 90] = 0x0277abdcdab07d5a77ac6d6b9fffffffff;
    maxExpArray[ 91] = 0x025daf6654b1eaa55fd64df5efffffffff;
    maxExpArray[ 92] = 0x0244c49c648baa98192dce88b7ffffffff;
    maxExpArray[ 93] = 0x022ce03cd5619a311b2471268bffffffff;
    maxExpArray[ 94] = 0x0215f77c045fbe885654a44a0fffffffff;
    maxExpArray[ 95] = 0x01ffffffffffffffffffffffffffffffff;
    maxExpArray[ 96] = 0x01eaefdbdaaee7421fc4d3ede5ffffffff;
    maxExpArray[ 97] = 0x01d6bd8b2eb257df7e8ca57b09bfffffff;
    maxExpArray[ 98] = 0x01c35fedd14b861eb0443f7f133fffffff;
    maxExpArray[ 99] = 0x01b0ce43b322bcde4a56e8ada5afffffff;
    maxExpArray[100] = 0x019f0028ec1fff007f5a195a39dfffffff;
    maxExpArray[101] = 0x018ded91f0e72ee74f49b15ba527ffffff;
    maxExpArray[102] = 0x017d8ec7f04136f4e5615fd41a63ffffff;
    maxExpArray[103] = 0x016ddc6556cdb84bdc8d12d22e6fffffff;
    maxExpArray[104] = 0x015ecf52776a1155b5bd8395814f7fffff;
    maxExpArray[105] = 0x015060c256cb23b3b3cc3754cf40ffffff;
    maxExpArray[106] = 0x01428a2f98d728ae223ddab715be3fffff;
    maxExpArray[107] = 0x013545598e5c23276ccf0ede68034fffff;
    maxExpArray[108] = 0x01288c4161ce1d6f54b7f61081194fffff;
    maxExpArray[109] = 0x011c592761c666aa641d5a01a40f17ffff;
    maxExpArray[110] = 0x0110a688680a7530515f3e6e6cfdcdffff;
    maxExpArray[111] = 0x01056f1b5bedf75c6bcb2ce8aed428ffff;
    maxExpArray[112] = 0x00faadceceeff8a0890f3875f008277fff;
    maxExpArray[113] = 0x00f05dc6b27edad306388a600f6ba0bfff;
    maxExpArray[114] = 0x00e67a5a25da41063de1495d5b18cdbfff;
    maxExpArray[115] = 0x00dcff115b14eedde6fc3aa5353f2e4fff;
    maxExpArray[116] = 0x00d3e7a3924312399f9aae2e0f868f8fff;
    maxExpArray[117] = 0x00cb2ff529eb71e41582cccd5a1ee26fff;
    maxExpArray[118] = 0x00c2d415c3db974ab32a51840c0b67edff;
    maxExpArray[119] = 0x00bad03e7d883f69ad5b0a186184e06bff;
    maxExpArray[120] = 0x00b320d03b2c343d4829abd6075f0cc5ff;
    maxExpArray[121] = 0x00abc25204e02828d73c6e80bcdb1a95bf;
    maxExpArray[122] = 0x00a4b16f74ee4bb2040a1ec6c15fbbf2df;
    maxExpArray[123] = 0x009deaf736ac1f569deb1b5ae3f36c130f;
    maxExpArray[124] = 0x00976bd9952c7aa957f5937d790ef65037;
    maxExpArray[125] = 0x009131271922eaa6064b73a22d0bd4f2bf;
    maxExpArray[126] = 0x008b380f3558668c46c91c49a2f8e967b9;
    maxExpArray[127] = 0x00857ddf0117efa215952912839f6473e6;

'''
    @dev given a token supply, reserve, CRR and a deposit amount (in the reserve token), calculates the return for a given change (in the main token)

    Formula:
    Return = _supply * ((1 + _depositAmount / _reserveBalance) ^ (_reserveRatio / 1000000) - 1)

    @param _supply             token total supply
    @param _reserveBalance     total reserve
    @param _reserveRatio       constant reserve ratio, represented in ppm, 1-1000000
    @param _depositAmount      deposit amount, in reserve token

    @return purchase return amount
'''
def calculatePurchaseReturn(_supply, _reserveBalance, _reserveRatio, _depositAmount):
    # validate input
    assert(_supply > 0 and _reserveBalance > 0 and _reserveRatio > 0 and _reserveRatio <= MAX_CRR);

    # special case for 0 deposit amount
    if (_depositAmount == 0):
        return 0;

    # special case if the CRR = 100%
    if (_reserveRatio == MAX_CRR):
        return safeMul(_supply, _depositAmount) / _reserveBalance;

    baseN = safeAdd(_depositAmount, _reserveBalance);
    (result, precision) = power(baseN, _reserveBalance, _reserveRatio, MAX_CRR);
    temp = safeMul(_supply, result) >> precision;
    return temp - _supply;

'''
    @dev given a token supply, reserve, CRR and a sell amount (in the main token), calculates the return for a given change (in the reserve token)

    Formula:
    Return = _reserveBalance * (1 - (1 - _sellAmount / _supply) ^ (1 / (_reserveRatio / 1000000)))

    @param _supply             token total supply
    @param _reserveBalance     total reserve
    @param _reserveRatio       constant reserve ratio, represented in ppm, 1-1000000
    @param _sellAmount         sell amount, in the token itself

    @return sale return amount
'''
def calculateSaleReturn(_supply, _reserveBalance, _reserveRatio, _sellAmount):
    # validate input
    assert(_supply > 0 and _reserveBalance > 0 and _reserveRatio > 0 and _reserveRatio <= MAX_CRR and _sellAmount <= _supply);

    # special case for 0 sell amount
    if (_sellAmount == 0):
        return 0;

    # special case for selling the entire supply
    if (_sellAmount == _supply):
        return _reserveBalance;

    # special case if the CRR = 100%
    if (_reserveRatio == MAX_CRR):
        return safeMul(_reserveBalance, _sellAmount) / _supply;

    baseD = _supply - _sellAmount;
    (result, precision) = power(_supply, baseD, MAX_CRR, _reserveRatio);
    temp1 = safeMul(_reserveBalance, result);
    temp2 = _reserveBalance << precision;
    return (temp1 - temp2) / result;

'''
    General Description:
        Determine a value of precision.
        Calculate an integer approximation of (_baseN / _baseD) ^ (_expN / _expD) * 2 ^ precision.
        Return the result along with the precision used.
    Detailed Description:
        Instead of calculating "base ^ exp", we calculate "e ^ (ln(base) * exp)".
        The value of "ln(base)" is represented with an integer slightly smaller than "ln(base) * 2 ^ precision".
        The larger "precision" is, the more accurately this value represents the real value.
        However, the larger "precision" is, the more bits are required in order to store this value.
        And the exponentiation function, which takes "x" and calculates "e ^ x", is limited to a maximum exponent (maximum value of "x").
        This maximum exponent depends on the "precision" used, and it is given by "maxExpArray[precision] >> (MAX_PRECISION - precision)".
        Hence we need to determine the highest precision which can be used for the given input, before calling the exponentiation function.
        This allows us to compute "base ^ exp" with maximum accuracy and without exceeding 256 bits in any of the intermediate computations.
'''
def power(_baseN, _baseD, _expN, _expD):
    lnBaseTimesExp = ln(_baseN, _baseD) * _expN / _expD;
    precision = findPositionInMaxExpArray(lnBaseTimesExp);
    return (fixedExp(lnBaseTimesExp >> (MAX_PRECISION - precision), precision), precision);

'''
    Return floor(ln(numerator / denominator) * 2 ^ MAX_PRECISION), where:
    - The numerator   is a value between 1 and 2 ^ (256 - MAX_PRECISION) - 1
    - The denominator is a value between 1 and 2 ^ (256 - MAX_PRECISION) - 1
    - The output      is a value between 0 and floor(ln(2 ^ (256 - MAX_PRECISION) - 1) * 2 ^ MAX_PRECISION)
    This functions assumes that the numerator is larger than or equal to the denominator, because the output would be negative otherwise.
'''
def ln(_numerator, _denominator):
    assert(_numerator <= MAX_NUM);

    res = 0;
    x = _numerator * FIXED_1 / _denominator;

    # If x >= 2, then we compute the integer part of log2(x), which is larger than 0.
    if (x >= FIXED_2):
        count = floorLog2(x / FIXED_1);
        x >>= count; # now x < 2
        res = count * FIXED_1;

    # If x > 1, then we compute the fraction part of log2(x), which is larger than 0.
    if (x > FIXED_1):
        for i in range(MAX_PRECISION, 0, -1):
            x = (x * x) / FIXED_1; # now 1 < x < 4
            if (x >= FIXED_2):
                x >>= 1; # now 1 < x < 2
                res += ONE << (i - 1);

    return (res * LN2_MANTISSA) >> LN2_EXPONENT;

'''
    Compute the largest integer smaller than or equal to the binary logarithm of the input.
'''
def floorLog2(_n):
    res = 0;

    if (_n < 256):
        # At most 8 iterations
        while (_n > 1):
            _n >>= 1;
            res += 1;
    else:
        # Exactly 8 iterations
        for s in [1 << (8 - 1 - k) for k in range(8)]:
            if (_n >= (ONE << s)):
                _n >>= s;
                res |= s;

    return res;

'''
    The global "maxExpArray" is sorted in descending order, and therefore the following statements are equivalent:
    - This function finds the position of [the smallest value in "maxExpArray" larger than or equal to "x"]
    - This function finds the highest position of [a value in "maxExpArray" larger than or equal to "x"]
'''
def findPositionInMaxExpArray(_x):
    lo = MIN_PRECISION;
    hi = MAX_PRECISION;

    while (lo + 1 < hi):
        mid = (lo + hi) / 2;
        if (maxExpArray[mid] >= _x):
            lo = mid;
        else:
            hi = mid;

    if (maxExpArray[hi] >= _x):
        return hi;
    if (maxExpArray[lo] >= _x):
        return lo;

    assert(False);
    return 0;

'''
    This function can be auto-generated by the script 'PrintFunctionFixedExp.py'.
    It approximates "e ^ x" via maclaurin summation: "(x^0)/0! + (x^1)/1! + ... + (x^n)/n!".
    It returns "e ^ (x >> precision) << precision", that is, the result is upshifted for accuracy.
    The global "maxExpArray" maps each "precision" to "((maximumExponent + 1) << (MAX_PRECISION - precision)) - 1".
    The maximum permitted value for "x" is therefore given by "maxExpArray[precision] >> (MAX_PRECISION - precision)".
'''
def fixedExp(_x, _precision):
    xi = _x;
    res = 0;

    xi = (xi * _x) >> _precision;
    res += xi * 0x3442c4e6074a82f1797f72ac0000000;
    xi = (xi * _x) >> _precision;
    res += xi * 0x116b96f757c380fb287fd0e40000000;
    xi = (xi * _x) >> _precision;
    res += xi * 0x45ae5bdd5f0e03eca1ff4390000000;
    xi = (xi * _x) >> _precision;
    res += xi * 0xdefabf91302cd95b9ffda50000000;
    xi = (xi * _x) >> _precision;
    res += xi * 0x2529ca9832b22439efff9b8000000;
    xi = (xi * _x) >> _precision;
    res += xi * 0x54f1cf12bd04e516b6da88000000;
    xi = (xi * _x) >> _precision;
    res += xi * 0xa9e39e257a09ca2d6db51000000;
    xi = (xi * _x) >> _precision;
    res += xi * 0x12e066e7b839fa050c309000000;
    xi = (xi * _x) >> _precision;
    res += xi * 0x1e33d7d926c329a1ad1a800000;
    xi = (xi * _x) >> _precision;
    res += xi * 0x2bee513bdb4a6b19b5f800000;
    xi = (xi * _x) >> _precision;
    res += xi * 0x3a9316fa79b88eccf2a00000;
    xi = (xi * _x) >> _precision;
    res += xi * 0x48177ebe1fa812375200000;
    xi = (xi * _x) >> _precision;
    res += xi * 0x5263fe90242dcbacf00000;
    xi = (xi * _x) >> _precision;
    res += xi * 0x57e22099c030d94100000;
    xi = (xi * _x) >> _precision;
    res += xi * 0x57e22099c030d9410000;
    xi = (xi * _x) >> _precision;
    res += xi * 0x52b6b54569976310000;
    xi = (xi * _x) >> _precision;
    res += xi * 0x4985f67696bf748000;
    xi = (xi * _x) >> _precision;
    res += xi * 0x3dea12ea99e498000;
    xi = (xi * _x) >> _precision;
    res += xi * 0x31880f2214b6e000;
    xi = (xi * _x) >> _precision;
    res += xi * 0x25bcff56eb36000;
    xi = (xi * _x) >> _precision;
    res += xi * 0x1b722e10ab1000;
    xi = (xi * _x) >> _precision;
    res += xi * 0x1317c70077000;
    xi = (xi * _x) >> _precision;
    res += xi * 0xcba84aafa00;
    xi = (xi * _x) >> _precision;
    res += xi * 0x82573a0a00;
    xi = (xi * _x) >> _precision;
    res += xi * 0x5035ad900;
    xi = (xi * _x) >> _precision;
    res += xi * 0x2f881b00;
    xi = (xi * _x) >> _precision;
    res += xi * 0x1b29340;
    xi = (xi * _x) >> _precision;
    res += xi * 0xefc40;
    xi = (xi * _x) >> _precision;
    res += xi * 0x7fe0;
    xi = (xi * _x) >> _precision;
    res += xi * 0x420;
    xi = (xi * _x) >> _precision;
    res += xi * 0x21;
    xi = (xi * _x) >> _precision;
    res += xi * 0x1;

    return res / 0x688589cc0e9505e2f2fee5580000000 + _x + (ONE << _precision);


def safeMul(x,y):
    assert(x * y < (1 << 256))
    return x * y


def safeAdd(x,y):
    assert(x + y < (1 << 256))
    return x + y


def safeSub(x,y):
    assert(x - y >= 0)
    return x - y


BancorFormula()
